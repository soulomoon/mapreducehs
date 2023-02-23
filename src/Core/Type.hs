{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Core.Type where
import Control.Concurrent
import GHC.Generics
import Data.Binary

data EvaluateType
  = LocalSimple
  | LocalMultipleWorkers

data WorkerType = VirtualWorker | ActualWorker

data StoreType = MemoryStore | LocalFileStore

data ServerState = Running | Stopped

data ServerContext = ServerContext
  { 
    cIn :: Chan Context,
    cOut :: Chan Context,
    serverState :: MVar  ServerState
  }

data Context = Context { 
    _workerCountL :: Int,
    _taskIdL :: Int,
    _spaceNameL :: String,
    _dirNameL :: String,
    _partitionIdL :: Int
} deriving (Show, Generic, Binary, Eq)
