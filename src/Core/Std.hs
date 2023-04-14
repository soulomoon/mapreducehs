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

import Core.Context
import Core.MapReduceC
import Core.Partition
import Control.Monad.State
import Core.Serialize
import Core.Store (MonadStore)
import Core.Type (StoreType)

-- should increase id before send
evalOne :: forall t context m. (PartitionConstraint t context m) => EvalPair -> m ()
evalOne (EvalPair mr d) = incrTaskId @context >> sendDataToPartitions @t (mr d)

runCtx:: Monad m => context -> StateT context m a -> m a
runCtx context =  (`evalStateT` context)

-- collect result and send to a new partition
sendResult :: forall (t :: StoreType) context k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadStore t context m) => MapReduce k1 v1 k3 v3 -> m ()
sendResult _ = do
    dd <- getAllDataTup @t @context @k3 @v3
    liftIO $ print dd
    incrTaskId @context
    sendDataToPartition @t @context 0 dd

getResult :: forall (t :: StoreType) context k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadStore t context m) => MapReduce k1 v1 k3 v3 -> m [(k3, v3)]
getResult _ = getAllDataTup @t @context @k3 @v3

doTask :: forall t context m k1 v1 k3 v3. (PartitionConstraint t context m, Serializable2 k1 v1, Serializable2 k3 v3)  =>
  MapReduce k1 v1 k3 v3 -> m ()
doTask mr = do
      -- files <- findTaskFiles
      tid <- taskId @context
      ps <- indexMR tid mr $ getDataFromPartition @t 
      forM_ ps (evalOne @t)

-- use do task
runTask ::
  forall (t :: StoreType) context k1 v1 k3 v3.
  (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context (StateT context IO)) =>
  MapReduce k1 v1 k3 v3 ->
  context ->
  IO ()
runTask mr ctx = runCtx ctx $ (doTask @t @context) mr


runTaskM ::
  forall (t :: StoreType) m context k1 v1 k3 v3.
  (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context (StateT context m), Monad m) =>
  MapReduce k1 v1 k3 v3 ->
  context ->
  m ()
runTaskM mr ctx = runCtx ctx $ (doTask @t @context) mr

a :: (b -> c -> d) -> (a1 -> a2 -> a3 -> b) -> a1 -> a2 -> a3 -> c -> d
a =  (.) . (.) . (.)
-- a =  (.) . (.) . (.) . (.)
-- c = (.) ~ (.)