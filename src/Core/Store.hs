{-# LANGUAGE ConstrainedClassMethods #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Core.Store where

import Control.Monad.Cont
import Core.Context
import Core.Serialize
import Data.List (isSuffixOf)
import System.Directory (listDirectory)
import System.IO

-- handles IO

data StoreType = MemoryStore | LocalFileStore

class (MonadContext m, MonadIO m) => MonadStore (t :: StoreType) m where
  findAllTaskFiles :: m [String] -- | a lift of file names
  findAllTaskFiles = do
    tId <- taskId
    -- suffix is the taskId
    findTaskFileWith @t ("-" ++ show tId)
  findTaskFiles :: m [String] -- | a lift of file names
  findTaskFiles = do
    wId <- partitionId
    tId <- taskId
    -- partitionId(worker Id), taskId
    liftIO $ putStrLn $ "-" ++ show wId ++ "-" ++ show tId
    findTaskFileWith @t ("-" ++ show wId ++ "-" ++ show tId)

  -- sending path is current workerId, next workerId, taskId
  mkFilePath :: (Show a) => a -> m String
  mkFilePath pid = do
    wId <- partitionId
    tId <- taskId
    dir <- dirName
    space <- spaceName
    return $ concat [dir, "/", space, "-", show wId, "-", show pid, "-", show tId]

  findTaskFileWith :: String -> m [String]
  writeToFile :: String -> String -> m ()
  getDataFromFiles :: (Serializable2 k v) => m [String] -> m [(k, v)]
  getStringsFromFiles :: m [String] -> m [String]
-- local file store
instance (MonadContext m, MonadIO m) => MonadStore 'LocalFileStore m where
  findTaskFileWith pat = do
    dir <- dirName
    liftIO $ map ((dir ++ "/") ++) . filter (isSuffixOf pat) <$> listDirectory dir
  writeToFile path s = liftIO $ withFile path WriteMode (`hPutStr` s)
  getDataFromFiles mFiles = do
    files <- mFiles
    r <- liftIO (mapM (fmap unSerialize . readFile) files)
    liftIO $ print files
    return $ concat r

  getStringsFromFiles mFiles = do
    files <- mFiles
    r <- liftIO (mapM readFile files)
    return r

-- local file store