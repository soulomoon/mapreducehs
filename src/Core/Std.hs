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
evalOne :: forall t m. (PartitionConstraint t m) => EvalPair -> m ()
evalOne (EvalPair mr d) = incrTaskId @t >> sendDataToPartitions @t (mr d)

runCtx:: Monad m => context -> (StateT context m) a -> m a
runCtx context =  (`evalStateT` context)

-- collect result and send to a new partition
sendResult :: forall (t :: StoreType) k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadContext t m, MonadStore t m) => MapReduce k1 v1 k3 v3 -> m ()
sendResult _ = do
    dd <- getAllDataTup @t @k3 @v3
    liftIO $ print dd
    incrTaskId @t
    sendDataToPartition @t 0 dd

getResult :: forall (t :: StoreType) k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadContext t m, MonadStore t m) => MapReduce k1 v1 k3 v3 -> m [(k3, v3)]
getResult _ = getAllDataTup @t @k3 @v3

doTask :: forall t m k1 v1 k3 v3. (PartitionConstraint t m, Serializable2 k1 v1, Serializable2 k3 v3)  =>
  MapReduce k1 v1 k3 v3 -> m ()
doTask mr = do
      -- files <- findTaskFiles @t
      tid <- taskId @t
      ps <- indexMR tid mr $ getDataFromPartition @t
      forM_ ps (evalOne @t)

-- use do task
runTask ::
  forall (t :: StoreType) k1 v1 k3 v3 context.
  (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t (StateT context IO)) =>
  MapReduce k1 v1 k3 v3 ->
  context ->
  IO ()
runTask mr ctx = runCtx ctx $ (doTask @t) mr