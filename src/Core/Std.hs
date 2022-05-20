{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.Std where

import Control.Applicative
import Control.Concurrent (MVar, forkIO, newEmptyMVar, newChan)
import Control.Monad.State
import Core.Context
import Core.MapReduceC
import Core.Partition
import Core.Serialize (Serializable2)
import Core.Type
import Control.Monad.Reader (ReaderT (runReaderT))
import Core.Signal

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

class Runner (t :: EvaluateType) m where
  runMapReduce :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> [(k1, v1)] -> m [(k3, v3)]

instance (Monad m) => Runner 'LocalSimple m where
  runMapReduce mr d = fixM evaluateF (E d mr)

instance (Monad m, PartitionConstraint m, MonadContext m, MonadIO m, Has Context m) => Runner 'LocalMultipleWorkers m where
  runMapReduce mr kvs = undefined
    -- n <- workerCount
    -- c <- getC 
    -- signalsInList <- liftIO $ replicateM n newEmptyMVar
    -- signalsOutList <- liftIO $ replicateM n newEmptyMVar
    -- let widList = [0 .. n -1]
    -- workerContextList <-
    --       liftIO $ sequence $ getZipList $
    --         mkChildContext
    --           <$> ZipList (replicate n c)
    --           <*> ZipList widList
    --           <*> ZipList signalsInList
    --           <*> ZipList signalsOutList

    -- -- distribute the data
    -- sendDataToPartitions kvs
    -- -- setup workers
    -- mapM_ (liftIO . forkIO . runWorker mr) workerContextList
    -- -- setup server
    -- masterGo mr signalsInList signalsOutList
    -- return ()
    -- getAllData

masterGo :: forall k1 v1 k3 v3 m. (Monad m, MonadIO m, MonadContext m) => MapReduce k1 v1 k3 v3 -> [MVar ()] -> [MVar ()] -> m ()
masterGo mr taskList doneList = 

  mapM_ putSignal taskList >>
  masterLoop mr >> mapM_ getSignal doneList >> incrTaskId
  where
    masterLoop :: MapReduce k2 v2 k3 v3 -> m ()
    masterLoop MrOut = return ()
    masterLoop (r :> _) = do
      incrTaskId
      tid <- taskId
      mapM_ getSignal doneList
      -- liftIO $ print $ show tid
      mapM_ putSignal taskList
      masterLoop r

mkChildContext :: Context -> Int -> MVar () -> MVar () -> IO (Signals, Context)
mkChildContext config wid a b = do 
  c <- newChan
  return (Signals a b c, config {_partitionIdL = wid})

runWorker ::
  forall m k1 v1 k3 v3.
  ( Serializable2 k1 v1,
    Serializable2 k3 v3,
    Monad m,
    MonadIO m
  ) =>
  MapReduce k1 v1 k3 v3 ->
  (Signals, Context) ->
  m ()
runWorker mr (sig, c) = runContext (sig, c) $ do
  tid <- taskId
  -- context would be injected in the wait
  wait
  _ <- evaluate =<< indexMapReduce tid mr getDataFromPartition
  return ()

runWithContext :: (Monad m, MonadIO m, Serializable2 k1 v1, Serializable2 k3 v3) => (Signals, Context) -> MapReduce k1 v1 k3 v3 -> [(k1, v1)] -> m [(k3, v3)]
runWithContext c mr df = runContext c $ runMapReduce @'LocalMultipleWorkers mr df

runContext :: Monad m => (Signals, Context) -> ReaderT Signals (StateT Context m) a -> m a
runContext (sig, context) =  (`evalStateT` context) . (`runReaderT` sig) 