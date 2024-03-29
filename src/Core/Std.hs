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
import Control.Monad.Reader (ReaderT (runReaderT))


runCtx:: Monad m => context -> ReaderT context m a -> m a
runCtx context =  (`runReaderT` context)

-- collect result and send to a new partition
-- todo it is conventional to send to partition 0
sendResult :: forall (t :: StoreType) context k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadStore t context m) => MapReduce k1 v1 k3 v3 -> m [(k3, v3)]
sendResult _ = do
    dd <- getAllDataTup @t @context @k3 @v3
    logg $ "final sendResult" ++ show dd
    incrTaskId @context $ sendDataToPartition @t @context 0 dd
    return dd

getResult :: forall (t :: StoreType) context m k1 v1 k3 v3 . (Serializable2 k3 v3, MonadStore t context m) => MapReduce k1 v1 k3 v3 -> m [(k3, v3)]
getResult _ = getAllDataTup @t @context @k3 @v3

-- runTaskM ::
--   forall (t :: StoreType) m context k1 v1 k3 v3.
--   (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context m, Monad m) =>
--   MapReduce k1 v1 k3 v3 ->
--   context ->
--   m ()
-- runTaskM mr ctx = runCtx ctx $ (doTask @t @context) mr

-- should increase id before send
evalOne :: forall t context m a. (PartitionConstraint t context m) => () -> EvalPair -> m ()
evalOne _ (EvalPair mr d) = incrTaskId @context $ sendDataToPartitions @t (mr d)

doTask :: forall t context m k1 v1 k3 v3. (PartitionConstraint t context m, Serializable2 k1 v1, Serializable2 k3 v3)  =>
  MapReduce k1 v1 k3 v3 -> m ()
doTask mr = do
      tid <- taskId @context
      ps <- indexMR tid mr $ getDataFromPartition @t
      fold1M_ (evalOne @t) ps

fold1M_ f = foldM_ f ()

