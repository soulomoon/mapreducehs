-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module Main where

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, writeList2Chan, forkIO, getChanContents, newChan, threadDelay)
import qualified Control.Exception as E
import Data.Binary (encode, decode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll, recv)
import Core.Context 
import Core.MapReduceC
import Control.Monad.State
import Core.Partition
import Impl
import Core.Std
import Core.Store


main :: IO ()
main = do
  let len = pipeLineLength sampleReduce
  putStrLn $ "mr length: " ++ show len
  cIn <- newChan
  cOut <- newChan
  let cxt = genContext 5 sampleReduce
  -- send  data to the all possible partitions to initialize the test
  runCtx (Context 5 0 "task" "tempdata" 0) $ sendDataToPartitions @'LocalFileStore sample
  -- fork all the workers
  runAllWorkers cIn cOut cxt
  -- act as server to send all tasks
  sendTask cIn cOut cxt
  -- collect all the result
  runCtx (Context 5 len "task" "tempdata" 0) $ sendResult @'LocalFileStore sampleReduce


-- keep putting task to the out channel
-- and read the result from the in channel
sendTask ::  Chan Context -> Chan Context -> [[Context]] -> IO ()
-- invalid task to end the worker
sendTask _ cOut [] = 
  writeChan cOut (Context (-1) (-1) "task" "tempdata" (-1)) >> threadDelay 1000 
sendTask cIn cOut (x:xs) = do 
  putStrLn "putting to chan"
  print x
  writeList2Chan cOut x 
  putStrLn "putting to chan done"
  -- take all of the send task back from the channel
  ys <- take (length x) <$> getChanContents cIn 
  -- loop
  sendTask cIn cOut xs

runAllWorkers ::  Chan Context -> Chan Context -> [[Context]] -> IO ()
runAllWorkers cIn cOut cxts = do
  print "starting workers"
  replicateM_ 5 $ forkIO $ runLocalWorker cIn cOut


validWork :: Context -> Bool
validWork = (>= 0) . _taskIdL

runLocalWorker :: Chan Context -> Chan Context -> IO ()
runLocalWorker cIn cOut = do
  context <- readChan cOut
  when (validWork context) $ 
    runTask @'LocalFileStore sampleReduce context 
    >> writeChan cIn context 
    >> runLocalWorker cIn cOut



runServer :: Chan Context -> Chan Context -> IO ()
runServer cIn cOut = do 
  runTCPServer Nothing "3000" talk
  where
    talk s = do
      putStrLn "Client connected, sending:"
      context <- readChan cOut
      sendAll s (encode context)
      -- should timeout here
      response <- decode <$> recv s 10240
      print $ context == response
      writeChan cIn response
      

-- from the "network-run" package.
runTCPServer :: Maybe HostName -> ServiceName -> (Socket -> IO a) -> IO a
runTCPServer mhost port server = withSocketsDo $ do
  addr <- resolve
  E.bracket (open addr) close loop
  where
    resolve = do
      let hints =
            defaultHints
              { addrFlags = [AI_PASSIVE],
                addrSocketType = Stream
              }
      head <$> getAddrInfo (Just hints) mhost (Just port)
    open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
      setSocketOption sock ReuseAddr 1
      withFdSocket sock setCloseOnExecIfNeeded
      bind sock $ addrAddress addr
      listen sock 1024
      return sock
    loop sock = forever $
      E.bracketOnError (accept sock) (close . fst) $
        \(conn, _peer) ->
          void $
            -- 'forkFinally' alone is unlikely to fail thus leaking @conn@,
            -- but 'E.bracketOnError' above will be necessary if some
            -- non-atomic setups (e.g. spawning a subprocess to handle
            -- @conn@) before proper cleanup of @conn@ is your case
            forkFinally (server conn) (const $ gracefulClose conn 5000)