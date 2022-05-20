{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.Worker where
import Core.MapReduceC
import Core.Signal
import Core.Context
import Core.Serialize
import Core.Partition (PartitionConstraint, sendDataToPartitions, getDataFromPartition)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State
import Control.Monad.Reader (ReaderT (runReaderT), MonadReader)


data WorkerType = VirtualWorker | ActualWorker

-- standard implementation of running the interpreter

-- main spawn virtual workers, each virtual workers invoke working on different real workers
-- real worker may die, virtual worker never dies.
-- 1. virtual worker spawn a new thread to timeout the virtual worker
-- 2. virtual worker send signal to worker to start working.
-- 3. virtual worker wait for the worker to response.

-- evaluator extension
evId :: forall m k v. (Serializable2 k v, MonadContext m, Monad m) => Trans m k v
evId ev ev' e = incrTaskId >> ev ev' e

evPartition :: forall m k v. (PartitionConstraint m, MonadSignal m) => Trans m k v
evPartition ev ev' (E df g) =
  do
    -- send to partition
    sendDataToPartitions df
    done
    wait
    tid <- taskId
    wid <- partitionId
    liftIO $ print $ "tid: " ++ show tid ++ ", wid: " ++ show wid ++ ": " ++ show df
    -- get from partition
    newDf <- getDataFromPartition
    -- apply with the new data
    r <- ev ev' $ E newDf g
    done
    return r

evaluate :: forall m k v. (PartitionConstraint m, Serializable2 k v, MonadSignal m) => Evaluator m k v
evaluate = fixM (evId $ evPartition evaluateF)

-- should increase id before send
evalOne :: (PartitionConstraint m) => EvalPair -> m ()
evalOne (EvalPair mr d) = incrTaskId >> sendDataToPartitions (mr d)
    

class Worker (w :: WorkerType) m where
    getTask :: m Context
    runWorker :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> m ()

-- virtual worker just send the task to the remote.
instance (MonadIO m, PartitionConstraint m, MonadReader Signals m) => Worker 'VirtualWorker m where
    getTask = askTask
    runWorker mr = loop
      where
        loop = do
          context <- askTask
          let tid = _taskIdL context
          ps <- indexMR tid mr getDataFromPartition
          case ps of
            Just x -> evalOne x >> loop
            Nothing -> return ()

-- actual worker would wait for the master for the task
instance (PartitionConstraint m, MonadReader Signals m) => Worker 'ActualWorker m where
    getTask = askTask
    runWorker mr = loop
      where
        loop = do
          context <- askTask
          let tid = _taskIdL context
          ps <- indexMR tid mr getDataFromPartition
          case ps of
            Just x -> evalOne x >> loop
            Nothing -> return ()
    
runContext :: Monad m => (Signals, Context) -> ReaderT Signals (StateT Context m) a -> m a
runContext (sig, context) =  (`evalStateT` context) . (`runReaderT` sig) 


