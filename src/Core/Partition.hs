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

type PartitionConstraint m = (MonadStore m, MonadIO m)

logg :: (Show a, MonadIO m) => a -> m ()
logg = liftIO . print

-- Partition function
-- repartition after each operation
-- class (PartitionConstraint m) => Partitionable (t :: EvaluateType) m  where
sendDataToPartition :: (PartitionConstraint m, Serializable2 k v) => Int -> [(k, v)] -> m ()
sendDataToPartition pid kvs = do
  -- i <- taskId
  -- wi <- workerId
  -- liftIO $ putStrLn $  "workid " ++ show wi ++ " task " ++ show i ++ ", partition "++ show k ++ ":" ++ show kvs
  path <- mkFilePath pid
  writeToFile path $ serialize kvs

getDataFromPartition :: (Serializable2 k v, MonadStore m) => m [(k, v)]
getDataFromPartition = getDataFromFiles findTaskFiles

getAllData ::(MonadStore m) =>  m [String]
getAllData = getStringsFromFiles findAllTaskFiles

getAllDataTup ::(Serializable2 k v, MonadStore m) =>  m [(k, v)]
getAllDataTup = getDataFromFiles findAllTaskFiles

divides :: (PartitionConstraint m, Serializable2 k v) => [(k, v)] -> m (Map Int [(k, v)])
divides xs = do
  n <- workerCount
  -- liftIO $ print n
  return $ toMap $ map (\e@(k, _) -> (hash k `mod` n, e)) xs

-- send data to task
sendDataToPartitions :: (PartitionConstraint m, Serializable2 k v) => [(k, v)] -> m ()
sendDataToPartitions kvs = do
  parts <- divides kvs
  _ <- traverseWithKey sendDataToPartition parts
  return ()
