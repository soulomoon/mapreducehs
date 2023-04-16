
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
  allTaskDataPat :: m String
  allTaskDataPat = do
    tId <- taskId @context
    -- suffix is the taskId
    return ("-" ++ show tId)
  taskDataPat :: m String -- | a lift of file names
  taskDataPat = do
    wId <- partitionId @context
    tId <- taskId @context
    -- partitionId(worker Id), taskId
    liftIO $ putStrLn $ "-" ++ show wId ++ "-" ++ show tId
    return ("-" ++ show wId ++ "-" ++ show tId)
  -- sending path is current workerId, next workerId, taskId
  mkParPath :: (Show a, MonadContext context m) => a -> m String
  mkParPath pid = do
    wId <- partitionId @context
    tId <- taskId @context
    dir <- dirName @context
    space <- spaceName @context
    return $ concat [dir, "/", space, "-", show wId, "-", show pid, "-", show tId]

  writeToPar :: String -> String -> m ()
  getDataFromPat :: (Serializable2 k v) => m String -> m [(k, v)]
  -- getStringsFromFiles :: m [String] -> m [String]
-- local file store
instance (MonadContext Context m, MonadIO m) => MonadStore 'LocalFileStore Context m where
  writeToPar path s = liftIO $ withFile path WriteMode (`hPutStr` s)
  cleanUp = do
    dir <- dirName @Context
    e <- liftIO $ doesDirectoryExist dir
    when e $ liftIO (removeDirectoryRecursive dir)
    liftIO $ createDirectory dir
    return ()
  getDataFromPat patM = do
    pat <- patM
    dir <- dirName @Context
    files <- liftIO $ map ((dir ++ "/") ++) . filter (isSuffixOf pat) <$> listDirectory dir
    r <- liftIO (mapM readFile files)
    liftIO $ print files
    liftIO $ print r
    return $ concatMap unSerialize r


-- memory  store
-- using map
instance (MonadContext (Context, Map String String) m, MonadIO m, MonadState (Map String String) m) => MonadStore 'MemoryStore (Context, Map String String) m where
  cleanUp = modify (const mempty)
  getDataFromPat patM = do
    pat <- patM
    files <- gets (keys . filterWithKey (\k _ -> pat `isSuffixOf` k)) 
    fs <- get
    let content = (restrictKeys fs . Set.fromList) files
    return $ concatMap unSerialize content
  writeToPar path s = liftIO $ withFile path WriteMode (`hPutStr` s)


instance (MonadRedis m, MonadContext Context m, MonadIO m) => MonadStore 'RedisStore Context m where
  cleanUp = do
    d <- dirName @Context
    _ <- liftRedis $ Database.Redis.del [B.pack d]
    return ()

  writeToPar path s = do
    d <- dirName @Context
    _ <- liftRedis $ Database.Redis.hset (B.pack d) (B.pack path) (B.pack s)
    return ()

  getDataFromPat patM = do
    pat <- patM
    dir <- fromString <$> dirName @Context
    res <-liftRedis $ Database.Redis.hscanOpts dir Database.Redis.cursor0 ( Database.Redis.ScanOpts (Just $ B.pack ('*':pat)) (Just 1000))
    case res of
            -- todo handle error ?
            Left err -> error $ show err
            Right (_, xs) -> do
              return $ concatMap (unSerialize . B.unpack . snd) xs


instance {-# OVERLAPPABLE #-}
  ( MonadTrans t
  , MonadRedis m
  , Monad (t m)
  ) => MonadRedis (t m) where
  liftRedis = lift . liftRedis

