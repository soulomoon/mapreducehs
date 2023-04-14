{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}

-- Echo client program
module ImplWorker where

import qualified Control.Exception as E
import Network.Socket
import Network.Socket.ByteString.Lazy (recv, sendAll)
import Data.Binary (decode, encode, Binary)
import Core.MapReduceC 
import Core.Serialize (Serializable2)
import Impl
import Core.Store
import Control.Monad.Cont
import Core.Std 
import Core.Type (StoreType(LocalFileStore))
import Core.Logging
import UnliftIO.Async (mapConcurrently_)
import Control.Monad.State
import System.Random (randomRIO)
import Control.Concurrent (threadDelay)
import Core.Context(validWork)
import UnliftIO (MonadUnliftIO, Exception, catch, throwIO, bracket)

type TaskHandlerM (t :: StoreType) context m =  forall k1 v1 k3 v3 . (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context (StateT context m), Show context) => MapReduce k1 v1 k3 v3 -> context -> m ()

-- keep doing work
runClient :: 
  forall (t :: StoreType) context m k1 v1 k3 v3 .
  (MonadStore t context (StateT context m), Show context, Monad m, MonadIO m, MonadUnliftIO m) =>
  (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandlerM t context m-> MapReduce k1 v1 k3 v3 -> m ()
runClient doWork = runClientPort @t @context doWork myPort 


data DropException = DropException deriving (Show)
instance Exception DropException

runClientPort :: 
  forall (t :: StoreType) context m k1 v1 k3 v3 .
  (MonadStore t context (StateT context m), Show context, Monad m, MonadIO m, MonadUnliftIO m) =>
  (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandlerM t context m->  ServiceName -> MapReduce k1 v1 k3 v3 -> m ()
runClientPort doWork port mr = do
  b <- catch (runClientWork @t @context @m doWork port mr) 
    (\DropException -> logg "DropException" >> return True)
  when b $ runClientPort @t @context doWork port mr

runClientPortParallel :: 
  forall (t :: StoreType) context m k1 v1 k3 v3 .
  (MonadStore t context (StateT context m), Show context, MonadUnliftIO m, MonadUnliftIO m) =>
  (Serializable2 k1 v1, Serializable2 k3 v3) => Int -> TaskHandlerM t context m ->  ServiceName -> MapReduce k1 v1 k3 v3 -> m ()
runClientPortParallel n doWork  port mr = mapConcurrently_ (runClientPort @t @context doWork port) (replicate n mr)

runTaskLocal :: 
  forall (t :: StoreType) context m k1 v1 k3 v3.
  (MonadStore t context (StateT context m), Serializable2 k1 v1, Serializable2 k3 v3, Monad m) =>
  (MapReduce k1 v1 k3 v3 -> context -> m ())
runTaskLocal = runTaskM @t @m @context

runTaskLocalWithDrop :: 
  forall (t :: StoreType) context m.
  (MonadStore t context (StateT context m), MonadIO m) =>
  TaskHandlerM t context m
runTaskLocalWithDrop m n = do
  i :: Int <- randomRIO (1,10)
  logg $ "dropping task" ++ show n
  if i > 5 then logg "not dropping" >> runTaskM @t m n
  else throwIO DropException

runTaskLocalWithDelay :: 
  forall (t :: StoreType) context m.
  (MonadStore t context (StateT context m), Monad m, MonadIO m) =>
  Int -> TaskHandlerM t context m
runTaskLocalWithDelay dt m n = liftIO (threadDelay dt) >> (runTaskLocal @t @context @m) m n 


-- >>> 1 + 1
runClientWork  :: 
  forall (t :: StoreType) context m k1 v1 k3 v3.
  (Binary context, MonadStore t context (StateT context m), Serializable2 k1 v1, Serializable2 k3 v3, Show context, MonadIO m, MonadUnliftIO m) =>
  TaskHandlerM t context m -> ServiceName -> MapReduce k1 v1 k3 v3 -> m Bool
runClientWork runT port mr =
  runTCPClient "127.0.0.1" port $ \s -> do
  -- logg "getting"
  msg <- liftIO $ recv s 10240
  -- get the work
  let t = decode msg
  liftIO $ print t
  -- do the work for 1 second
  -- _ <- threadDelay 1000000
  if validWork @context t
    then runT mr t >> liftIO (sendAll s (encode t)) >> return True
    -- send back and end
    else liftIO (sendAll s (encode t)) >> return False

-- from the "network-run" package.
-- windows need withSocketsDo
runTCPClient :: (MonadIO m, MonadUnliftIO m) => HostName -> ServiceName -> (Socket -> m a) -> m a
runTCPClient host port client = do
  addr <- liftIO resolve
  bracket (liftIO $ open addr) (liftIO . close) client
  where
    resolve = do
      let hints = defaultHints {addrSocketType = Stream}
      head <$> getAddrInfo (Just hints) (Just host) (Just port)
    open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
      connect sock $ addrAddress addr
      return sock