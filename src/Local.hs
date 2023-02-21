-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module Main where

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, forkIO, newChan)
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
  runAllWorkers cIn cOut
  -- act as server to send all tasks
  sendTask cIn cOut cxt
  -- collect all the result
  runCtx (Context 5 len "task" "tempdata" 0) $ sendResult @'LocalFileStore sampleReduce


-- read from chan and run the sample reduce
runLocalWorker :: Chan Context -> Chan Context -> IO ()
runLocalWorker cIn cOut = do
  context <- readChan cOut
  when (validWork context) $ 
    runTask @'LocalFileStore sampleReduce context 
    >> writeChan cIn context 
    >> runLocalWorker cIn cOut

-- sample worker
runAllWorkers ::  Chan Context -> Chan Context -> IO ()
runAllWorkers cIn cOut = do
  print "starting workers"
  replicateM_ 5 $ forkIO $ runLocalWorker cIn cOut


-- handle the exception here if not receiving the result
runServer :: Chan Context -> Chan Context -> IO ()
runServer cIn cOut = do
  runTCPServer Nothing "3000" talk
  where
    talk s = do
      putStrLn "Client connected, sending task:"
      context <- readChan cOut
      sendAll s (encode context)
      -- only wait for the result when the task is valid
      -- otherwise, just send the next task
      when (validWork context)
        (do
          -- should timeout here
          response <- decode <$> recv s 10240
          -- should verify the response and do error handling
          print $ context == response
          writeChan cIn response)


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