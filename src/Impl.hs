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
import Data.List
import Control.Concurrent (writeChan, writeList2Chan, getChanContents, newChan, killThread, forkFinally, readChan, newMVar)
import Core.Store (MonadStore (cleanUp))
import Core.Partition (sendDataToPartitions)
import Core.Std (sendResult, getResult)
import Control.Monad.State
import Data.Map (Map)
import Core.Type 
import Core.Serialize (Serializable2)
import Core.Logging
import System.Timeout (timeout)
import Core.Context (invalidContext, MonadContext (setContext), genContext, IsContext (initialContext, finalContext))

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

-- ignoring the error handling here, since chan is not likely to fail
-- keep putting task to the out channel
-- and read the result from the in channel
sendTask :: forall context m. (MonadContext context m, MonadIO m) => ServerContext context -> [[context]] -> m ()
-- setting the server state to Stopped, then send invalid context to end the workers
sendTask sc [] = do 
  -- sending invalid context to end the and set the server state to Stopped
  liftIO $ writeChan (cOut sc) (invalidContext @context)
  -- read back from the channel to wait for the worker to end
  liftIO $ void $ timeout (workerTimeout sc) $ readChan (cIn sc) 
-- >> threadDelay 1000
sendTask sc (x:xs) = do
  logg "putting to chan"
  liftIO $ writeList2Chan (cOut sc) x
  logg "putting to chan done"
  -- take all of the send task back from the channel
  -- todo check them if matching
  result <- take (length x) <$> liftIO (getChanContents (cIn sc))
  logg $ show result
  sendTask @context @m sc xs


splitNum :: Int
splitNum = 5

myPort :: String
myPort = "3000"

newtype ContextState m = ContextState (StateT (Context, Map String String) IO m)

runMapReduce :: forall (t::StoreType) ctx m k1 v1 k2 v2 . 
  (Serializable2 k1 v1
  , Serializable2 k2 v2
  , MonadStore t ctx m) =>
  [(k1, v1)]
  -> MapReduce k1 v1 k2 v2
  -> (ServerContext ctx -> IO ())
  -> m ()
runMapReduce s1 mr serverRun = do
  let len = pipeLineLength mr
  liftIO $ logg $ "mr length: " ++ show len
  sc <- ServerContext <$> liftIO newChan <*> liftIO newChan <*> liftIO (newMVar Running) <*> return 10000000
  let cxt = genContext @ctx splitNum len
  -- send data to the all possible partitions to initialize the test
  cleanUp @t @ctx >> sendDataToPartitions @t @ctx s1
  -- the server to send the task to the workers
  tid <- liftIO $ forkFinally (serverRun sc) (const $ logg "server done")
  -- -- send all tasks
  sendTask @ctx sc cxt 
  -- -- collect all the result
  setContext @ctx (finalContext len) >> sendResult @t mr
  -- -- async kill to release the resource
  liftIO $ killThread tid

runMapReduceAndGetResult :: forall (t::StoreType) ctx m k1 v1 k2 v2. 
  (Serializable2 k1 v1, Serializable2 k2 v2, MonadStore t ctx m, MonadContext ctx m) 
  => [(k1, v1)] 
  -> MapReduce k1 v1 k2 v2 
  -> (ServerContext ctx -> IO ()) 
  -> m [(k2, v2)]
runMapReduceAndGetResult s1 mr serverRun = do
  runMapReduce @t s1 mr serverRun
  -- todo runCtx (Context splitNum len "task" "tempdata" 0) $ 
  getResult @t mr

