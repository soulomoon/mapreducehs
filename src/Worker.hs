{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}

-- Echo client program
module Main where

import qualified Control.Exception as E
import Network.Socket
import Network.Socket.ByteString.Lazy (recv, sendAll)
import Data.Binary (decode, encode)
import Core.MapReduceC 
import Core.Serialize (Serializable2)
import Impl
import Core.Store
import Control.Monad.Cont
import Core.Std 
import Control.Concurrent
import Core.Type (StoreType(LocalFileStore))

main :: IO ()
main = runClient sampleReduce

-- keep doing work
runClient :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO ()
runClient mr = do
  b <- goOne mr
  when b $ runClient mr

goOne  :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO Bool
goOne mr =
  runTCPClient "127.0.0.1" myPort $ \s -> do
  putStrLn "getting"
  msg <- recv s 10240
  -- get the work
  let t = decode msg
  print t
  -- do the work for 1 second
  _ <- threadDelay 1000000
  if validWork t
    then runTask @'LocalFileStore mr t >> sendAll s (encode t) >> return True
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