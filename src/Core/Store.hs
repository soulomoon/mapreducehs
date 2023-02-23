
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
import Core.Type (StoreType (LocalFileStore, MemoryStore))

-- handles IO
class (MonadContext t m, MonadIO m) => MonadStore (t :: StoreType) m where
  cleanUp :: m ()
  findAllTaskFiles :: m [String] -- | a lift of file names
  findAllTaskFiles = do
    tId <- taskId @t
    -- suffix is the taskId
    findTaskFileWith @t ("-" ++ show tId)
  findTaskFiles :: m [String] -- | a lift of file names
  findTaskFiles = do
    wId <- partitionId @t
    tId <- taskId @t
    -- partitionId(worker Id), taskId
    liftIO $ putStrLn $ "-" ++ show wId ++ "-" ++ show tId
    findTaskFileWith @t ("-" ++ show wId ++ "-" ++ show tId)

  -- sending path is current workerId, next workerId, taskId
  mkFilePath :: (Show a, MonadContext t m) => a -> m String
  mkFilePath pid = do
    wId <- partitionId @t
    tId <- taskId @t
    dir <- dirName @t
    space <- spaceName @t
    return $ concat [dir, "/", space, "-", show wId, "-", show pid, "-", show tId]

  findTaskFileWith :: String -> m [String]
  writeToFile :: String -> String -> m ()
  getDataFromFiles :: (Serializable2 k v) => m [String] -> m [(k, v)]
  -- getStringsFromFiles :: m [String] -> m [String]
-- local file store
instance (MonadContext 'LocalFileStore m, MonadIO m) => MonadStore 'LocalFileStore m where
  findTaskFileWith pat = do
    dir <- dirName @'LocalFileStore
    liftIO $ map ((dir ++ "/") ++) . filter (isSuffixOf pat) <$> listDirectory dir
  writeToFile path s = liftIO $ withFile path WriteMode (`hPutStr` s)
  getDataFromFiles mFiles = do
    files <- mFiles
    r <- liftIO (mapM readFile files)
    liftIO $ print files
    return $ concat $ unSerialize <$> r

  -- getStringsFromFiles mFiles = do
  --   files <- mFiles
  --   liftIO (mapM readFile files)
  cleanUp = do
    dir <- dirName @'LocalFileStore
    e <- liftIO $ doesDirectoryExist dir
    if e then liftIO (removeDirectoryRecursive dir) else return ()
    liftIO $ createDirectory dir
    return ()

-- memory  store
-- using map
instance (MonadContext 'MemoryStore m, MonadIO m, MonadState (Map String String) m) => MonadStore 'MemoryStore m where
  cleanUp = modify (const mempty)
  findTaskFileWith pat = gets (keys . filterWithKey (\k _ -> pat `isSuffixOf` k))
  writeToFile p d = modify (insert p d)
  getDataFromFiles mfiles = do
    fs <- get
    content <- restrictKeys fs . Set.fromList <$> mfiles
    return $ concat $ unSerialize <$> content
