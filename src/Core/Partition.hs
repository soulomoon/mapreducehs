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

type PartitionConstraint t m = (MonadStore t m, MonadIO m)

logg :: (Show a, MonadIO m) => a -> m ()
logg = liftIO . print

-- Partition function
-- repartition after each operation
-- class (PartitionConstraint m) => Partitionable (t :: EvaluateType) m  where
sendDataToPartition :: forall t m k v.(PartitionConstraint t m, Serializable2 k v) => Int -> [(k, v)] -> m ()
sendDataToPartition pid kvs = do
  -- i <- taskId
  -- wi <- workerId
  -- liftIO $ putStrLn $  "workId " ++ show wi ++ " task " ++ show i ++ ", partition "++ show k ++ ":" ++ show kvs
  path <- mkFilePath @t pid
  writeToFile @t path $ serialize kvs

-- get only the data from the current partition
getDataFromPartition :: forall t k v m. (Serializable2 k v, MonadStore t m) => m [(k, v)]
getDataFromPartition = getDataFromFiles @t $ findTaskFiles @t

-- retrieve raw data
-- getAllData :: forall t m. (MonadStore t m) =>  m [String]
-- getAllData = getStringsFromFiles @t $ findAllTaskFiles @t

-- get data from files
getAllDataTup :: forall t k v m. (Serializable2 k v, MonadStore t m) =>  m [(k, v)]
getAllDataTup = getDataFromFiles @t (findAllTaskFiles @t)

divides :: forall t k v m. (PartitionConstraint t m, Serializable2 k v) => [(k, v)] -> m (Map Int [(k, v)])
divides xs = do
  n <- workerCount @t
  -- liftIO $ print n
  return $ toMap $ map (\e@(k, _) -> (hash k `mod` n, e)) xs

-- send data to task
sendDataToPartitions :: forall t m k v. (PartitionConstraint t m, Serializable2 k v) => [(k, v)] -> m ()
sendDataToPartitions kvs = do
  parts <- divides @t kvs
  _ <- traverseWithKey (sendDataToPartition @t) parts
  return ()
