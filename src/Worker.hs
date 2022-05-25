{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}

-- Echo client program
module Main where

import qualified Control.Exception as E
import Network.Socket
import Network.Socket.ByteString.Lazy (recv, sendAll)
import Data.Binary (decode, encode)
import Core.Context
import Control.Monad (when, forM_)
import Core.Partition (PartitionConstraint, getDataFromPartition)
import Core.MapReduceC (indexMR, MapReduce (MrOut, (:>)), ToM (toM))
import Core.Serialize (Serializable2)
import Control.Monad.IO.Class (liftIO)
import Data.List
import Impl
import Core.Store
import Control.Monad.Cont
import Core.Std 

main :: IO ()
main = runClient sampleReduce
-- main = runTask sampleReduce (Context 5 1 "task" "tempdata" 1)


doTask :: (PartitionConstraint m, Serializable2 k1 v1, Serializable2 k3 v3)  =>
  MapReduce k1 v1 k3 v3 -> m ()
doTask mr = do
      files <- findTaskFiles
      tid <- taskId
      ps <- indexMR tid mr getDataFromPartition
      forM_ ps evalOne



-- use do task
runTask ::  (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> Context -> IO ()
runTask mr ctx = do
  print ctx
  runCtx ctx $ doTask mr

validWork :: Context -> Bool
validWork = (>= 0) . _taskIdL

-- keep doing work
runClient :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO ()
runClient mr = do
  b <- goOne mr
  when b $ runClient mr

goOne  :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO Bool
goOne mr =
  runTCPClient "127.0.0.1" "3000" $ \s -> do
  putStrLn "getting"
  msg <- recv s 10240
  let t = decode msg
  print t
  if validWork t
    then runTask mr t >> sendAll s (encode t) >> return True
    else return False

-- from the "network-run" package.
runTCPClient :: HostName -> ServiceName -> (Socket -> IO a) -> IO a
runTCPClient host port client = withSocketsDo $ do
  addr <- resolve
  E.bracket (open addr) close client
  where
    resolve = do
      let hints = defaultHints {addrSocketType = Stream}
      head <$> getAddrInfo (Just hints) (Just host) (Just port)
    open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
      connect sock $ addrAddress addr
      return sock