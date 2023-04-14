
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Core.Store where

import Control.Monad.Cont
import Core.Context
import Core.Serialize
import Data.List (isSuffixOf)
import System.Directory (listDirectory, createDirectory, removeDirectoryRecursive, doesDirectoryExist)
import System.IO
import Control.Monad.State
import Data.Map (Map, insert)
import Data.Map.Strict (keys)
import Data.Map (filterWithKey)
import qualified Data.Set as Set
import Data.Map (restrictKeys)
import Core.Type (StoreType (LocalFileStore, MemoryStore, RedisStore), Context)
import Database.Redis (RedisCtx, del, hscanOpts, cursor0, ScanOpts (ScanOpts, scanMatch, scanCount), hset, hget, checkedConnect, defaultConnectInfo, runRedis, MonadRedis (liftRedis))
import Data.String (IsString(fromString))
import Control.Monad.Identity (Identity (runIdentity))
import qualified Data.ByteString.Char8 as B --to prevent name clash with Prelude
--to prevent name clash with Prelude
import Data.Maybe (mapMaybe, catMaybes)
import Data.Either (lefts, rights)


-- handles IO
class (MonadContext context m, MonadIO m) => MonadStore (t :: StoreType) context m | t -> context where
  cleanUp :: m ()
  findAllTaskFiles :: m [String] -- | a lift of file names
  findAllTaskFiles = do
    tId <- taskId @context
    -- suffix is the taskId
    findTaskFileWith @t @context ("-" ++ show tId)
  findTaskFiles :: m [String] -- | a lift of file names
  findTaskFiles = do
    wId <- partitionId @context
    tId <- taskId @context
    -- partitionId(worker Id), taskId
    liftIO $ putStrLn $ "-" ++ show wId ++ "-" ++ show tId
    findTaskFileWith @t @context ("-" ++ show wId ++ "-" ++ show tId)

  -- sending path is current workerId, next workerId, taskId
  mkFilePath :: (Show a, MonadContext context m) => a -> m String
  mkFilePath pid = do
    wId <- partitionId @context
    tId <- taskId @context
    dir <- dirName @context
    space <- spaceName @context
    return $ concat [dir, "/", space, "-", show wId, "-", show pid, "-", show tId]

  findTaskFileWith :: String -> m [String]
  writeToFile :: String -> String -> m ()
  getDataFromFiles :: (Serializable2 k v) => m [String] -> m [(k, v)]
  -- getStringsFromFiles :: m [String] -> m [String]
-- local file store
instance (MonadContext Context m, MonadIO m) => MonadStore 'LocalFileStore Context m where
  findTaskFileWith pat = do
    dir <- dirName @Context
    liftIO $ map ((dir ++ "/") ++) . filter (isSuffixOf pat) <$> listDirectory dir
  writeToFile path s = liftIO $ withFile path WriteMode (`hPutStr` s)
  getDataFromFiles mFiles = do
    files <- mFiles
    r <- liftIO (mapM readFile files)
    liftIO $ print files
    return $ concatMap unSerialize r

  -- getStringsFromFiles mFiles = do
  --   files <- mFiles
  --   liftIO (mapM readFile files)
  cleanUp = do
    dir <- dirName @Context
    e <- liftIO $ doesDirectoryExist dir
    if e then liftIO (removeDirectoryRecursive dir) else return ()
    liftIO $ createDirectory dir
    return ()

-- memory  store
-- using map
instance (MonadContext (Context, Map String String) m, MonadIO m, MonadState (Map String String) m) => MonadStore 'MemoryStore (Context, Map String String) m where
  cleanUp = modify (const mempty)
  findTaskFileWith pat = gets (keys . filterWithKey (\k _ -> pat `isSuffixOf` k))
  writeToFile p d = modify (insert p d)
  getDataFromFiles mfiles = do
    fs <- get
    content <- restrictKeys fs . Set.fromList <$> mfiles
    return $ concatMap unSerialize content


instance (MonadRedis m, MonadContext Context m, MonadIO m) => MonadStore 'RedisStore Context m where
  cleanUp = do 
    d <- dirName @Context
    _ <- liftRedis $ Database.Redis.del [B.pack d]
    return ()

  findTaskFileWith pat = do
    dir <- fromString <$> dirName @Context
    res <-liftRedis $ Database.Redis.hscanOpts dir Database.Redis.cursor0 ( Database.Redis.ScanOpts (Just $ B.pack pat) (Just 1000))
    case res of
            Left err -> error $ show err
            Right (_, xs) -> return $ map (B.unpack . snd) xs

  writeToFile path s = do 
    d <- dirName @Context
    _ <- liftRedis $ Database.Redis.hset (B.pack d) (B.pack path) (B.pack s)
    return ()

  getDataFromFiles mFiles = do
    -- todo could get directly by patterns instead of getting all keys
    files <-map B.pack <$> mFiles
    d <- B.pack <$> dirName @Context
    -- r <- mapMaybe runIdentity  <$> mapM (Database.Redis.hget d) files
    r <- liftRedis $ mapM (Database.Redis.hget d) files
    let res = map (unSerialize . B.unpack) (catMaybes $ rights r)
    return res

instance {-# OVERLAPPABLE #-}
  ( MonadTrans t
  , MonadRedis m
  , Monad (t m)
  ) => MonadRedis (t m) where
  liftRedis = lift . liftRedis


-- set redis key
go :: IO ()
go = do 
  conn <- checkedConnect defaultConnectInfo
  x <- runRedis conn $ Database.Redis.hset (B.pack "space") (B.pack "test") (B.pack "ok")
  print x
  return ()
