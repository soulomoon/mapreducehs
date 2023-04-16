{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Core.Partition where

import Control.Monad.IO.Class
import Core.Context
import Core.Serialize (Serializable (serialize), Serializable2)
import Core.Store
import Core.Util
import Data.Hashable
import Data.Map hiding (filter, map)
import Core.Type (StoreType)

type PartitionConstraint t context m = (MonadStore t context m, MonadIO m)

logg :: (Show a, MonadIO m) => a -> m ()
logg = liftIO . print

-- Partition function
-- repartition after each operation
-- class (PartitionConstraint m) => Partitionable (t :: EvaluateType) m  where
sendDataToPartition :: forall t context m k v.(PartitionConstraint t context m, Serializable2 k v) => Int -> [(k, v)] -> m ()
sendDataToPartition pid kvs = do
  -- i <- taskId
  -- wi <- workerId
  -- liftIO $ putStrLn $  "workId " ++ show wi ++ " task " ++ show i ++ ", partition "++ show k ++ ":" ++ show kvs
  path <- mkParPath @t @context pid
  writeToPar @t @context path $ serialize kvs

-- get only the data from the current partition
getDataFromPartition :: forall t context k v m. (Serializable2 k v, MonadStore t context m) => m [(k, v)]
getDataFromPartition = do
  r <- getDataFromPat @t $ taskDataPat @t 
  liftIO $ putStr "getDataFromPartition:"
  liftIO $ print r
  return r

-- get data from files
getAllDataTup :: forall t context k v m. (Serializable2 k v, MonadStore t context m) =>  m [(k, v)]
getAllDataTup = getDataFromPat @t (allTaskDataPat @t)

divides :: forall (t :: StoreType) context k v m. (PartitionConstraint t context m, Serializable2 k v) => [(k, v)] -> m (Map Int [(k, v)])
divides xs = do
  n <- workerCount @context
  -- liftIO $ print n
  return $ toMap $ map (\e@(k, _) -> (hash k `mod` n, e)) xs

-- send data to task
sendDataToPartitions :: forall t context m k v. (PartitionConstraint t context m, Serializable2 k v) => [(k, v)] -> m ()
sendDataToPartitions kvs = do
  liftIO $ print ("sending: " <> serialize kvs)
  parts <- divides @t kvs
  _ <- traverseWithKey (sendDataToPartition @t @context) parts
  return ()
