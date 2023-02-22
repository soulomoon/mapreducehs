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
import Control.Concurrent (Chan, writeChan, writeList2Chan, getChanContents, threadDelay, newChan, forkIO)
import Core.Store (MonadStore (cleanUp))
import Core.Partition (sendDataToPartitions, PartitionConstraint)
import Core.Std (runCtx, sendResult, getResult)
import Control.Monad.State
import Data.Map (Map)
import Core.Type (StoreType)
import Core.Serialize (Serializable2)

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

-- ignoring the error handling here, since chan is not likely to fail
-- keep putting task to the out channel
-- and read the result from the in channel
sendTask ::  Chan Context -> Chan Context -> [[Context]] -> IO ()
-- invalid task to end the worker
sendTask _ cOut [] = writeChan cOut (Context (-1) (-1) "task" "tempdata" (-1)) >> threadDelay 1000
sendTask cIn cOut (x:xs) = do
  putStrLn "putting to chan"
  print (length x)
  writeList2Chan cOut x
  putStrLn "putting to chan done"
  -- take all of the send task back from the channel
  result <- take (length x) <$> getChanContents cIn
  print result
  -- loop
  sendTask cIn cOut xs


splitNum :: Int
splitNum = 5

myPort :: String
myPort = "3000"

newtype ContextState m = ContextState (StateT (Context, Map String String) IO m)

runMapReduce :: forall (t::StoreType) k1 v1 k2 v2 . (Serializable2 k2 v2, MonadStore t (StateT Context IO)) => MapReduce k1 v1 k2 v2 -> (Chan Context -> Chan Context -> IO ()) -> IO ()
runMapReduce mr serverRun = do
  let len = pipeLineLength mr
  putStrLn $ "mr length: " ++ show len
  cIn <- newChan
  cOut <- newChan
  let cxt = genContext splitNum mr
  -- send  data to the all possible partitions to initialize the test
  runCtx (Context splitNum 0 "task" "tempdata" 0) $ cleanUp @t >> sendDataToPartitions @t sample
  -- the server to send the task to the workers
  _ <- forkIO (serverRun cIn cOut)
  -- send all tasks
  sendTask cIn cOut cxt
  -- collect all the result
  runCtx (Context splitNum len "task" "tempdata" 0) $ sendResult @t mr

runMapReduceAndGetResult :: forall (t::StoreType) k1 v1 k2 v2 . (Serializable2 k2 v2, MonadStore t (StateT Context IO)) => MapReduce k1 v1 k2 v2 -> (Chan Context -> Chan Context -> IO ()) -> IO [(k2, v2)]
runMapReduceAndGetResult mr serverRun = do
  let len = pipeLineLength mr
  _ <- runMapReduce @t mr serverRun
  runCtx (Context splitNum len "task" "tempdata" 0) $ getResult @t mr
