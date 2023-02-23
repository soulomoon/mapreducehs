-- implement using chan
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
module Impl where

import Core.MapReduceC
import Core.Context
import Data.List
import Control.Concurrent (Chan, writeChan, writeList2Chan, getChanContents, threadDelay, newChan, killThread, forkFinally, readChan, MVar, newMVar, modifyMVar_)
import Core.Store (MonadStore (cleanUp))
import Core.Partition (sendDataToPartitions, PartitionConstraint)
import Core.Std (runCtx, sendResult, getResult)
import Control.Monad.State
import Data.Map (Map)
import Core.Type 
import Core.Serialize (Serializable2)
import Core.Logging

mapper :: (String, String) -> [(Char, Int)]
mapper (_, v) = map (\xs -> (head xs, length xs)) $ group v

mapperAdd1 :: (Char, Int) -> [(Char, Int)]
mapperAdd1 (k, v) = [(k, v + 1)]

reducer :: Char -> [Int] -> [Int]
reducer _ xs = [sum xs]

sample :: [([Char], [Char])]
sample = [("", "hello")]
--     sample
-- sampleReduce :: MapReduce k1 v1 k3 v3
sampleReduce :: MapReduce [Char] [Char] Char Int
sampleReduce = MrOut :> toM reducer :> toM mapperAdd1 :> toM mapper

-- generate a list of context, each context is a task in the pipeline
genContext :: Int -> MapReduce k1 v1 k3 v3 -> [[Context]]
genContext nWorker mr =
  let k = pipeLineLength mr in
  [[Context nWorker tid "task" "tempdata" wid  | wid <- [0 .. nWorker-1] ] | tid <- [0 .. k-1]]

-- check if the task is valid
validWork :: Context -> Bool
validWork = (>= 0) . _taskIdL

invalidContext :: Context
invalidContext = Context (-1) (-1) "task" "tempdata" (-1)
-- ignoring the error handling here, since chan is not likely to fail
-- keep putting task to the out channel
-- and read the result from the in channel
sendTask :: ServerContext -> [[Context]] -> IO ()
-- setting the server state to Stopped, then send invalid context to end the workers
sendTask sc [] = do 
  -- sending invalid context to end the and set the server state to Stopped
  writeChan (cOut sc) invalidContext  
  -- read back from the channel to wait for the worker to end
  void $ readChan (cIn sc) 
-- >> threadDelay 1000
sendTask sc (x:xs) = do
  logg "putting to chan"
  writeList2Chan (cOut sc) x
  logg "putting to chan done"
  -- take all of the send task back from the channel
  -- todo check them if matching
  result <- take (length x) <$> getChanContents (cIn sc)
  logg $ show result
  sendTask sc xs


splitNum :: Int
splitNum = 5

myPort :: String
myPort = "3000"

newtype ContextState m = ContextState (StateT (Context, Map String String) IO m)

runMapReduce :: forall (t::StoreType) k1 v1 k2 v2 . (Serializable2 k1 v1, Serializable2 k2 v2, MonadStore t (StateT Context IO)) => [(k1, v1)] -> MapReduce k1 v1 k2 v2 -> (ServerContext -> IO ()) -> IO ()
runMapReduce s1 mr serverRun = do
  let len = pipeLineLength mr
  logg $ "mr length: " ++ show len
  sc <- ServerContext <$> newChan <*> newChan <*> newMVar Running
  let cxt = genContext splitNum mr
  -- send  data to the all possible partitions to initialize the test
  runCtx (Context splitNum 0 "task" "tempdata" 0) $ cleanUp @t >> sendDataToPartitions @t s1
  -- the server to send the task to the workers
  tid <- forkFinally (serverRun sc) (const $ logg "server done")
  -- tid <- forkIO (serverRun cIn cOut)
  -- send all tasks
  sendTask sc cxt
  -- collect all the result
  runCtx (Context splitNum len "task" "tempdata" 0) $ sendResult @t mr
  -- async kill to release the resource
  killThread tid

runMapReduceAndGetResult :: forall (t::StoreType) k1 v1 k2 v2 . (Serializable2 k1 v1, Serializable2 k2 v2, MonadStore t (StateT Context IO)) => [(k1, v1)] -> MapReduce k1 v1 k2 v2 -> (ServerContext -> IO ()) -> IO [(k2, v2)]
runMapReduceAndGetResult s1 mr serverRun = do
  let len = pipeLineLength mr
  runMapReduce @t s1 mr serverRun
  runCtx (Context splitNum len "task" "tempdata" 0) $ getResult @t mr

