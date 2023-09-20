{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeFamilyDependencies #-}

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
import Core.Std hiding (doTask)
import Core.Type (StoreType(LocalFileStore, RedisStore), Context)
import Core.Logging
import UnliftIO.Async (mapConcurrently_)
import Control.Monad.State
import System.Random (randomRIO)
import Control.Concurrent (threadDelay)
import Core.Context(validWork, initialContext, MonadContext (getContext, setContext))
import UnliftIO (MonadUnliftIO, Exception, catch, throwIO, bracket)
import Database.Redis (checkedConnect, defaultConnectInfo, runRedis)
import Control.Monad.Reader (MonadReader)
import Control.Monad.Trans.Reader (runReaderT)
import Core.Std (doTask)
import Core.Partition (PartitionConstraint)


data ClientType = Single | SingleDelay | Multi deriving (Show)
type TaskHandlerM (t :: StoreType) context m =  forall k1 v1 k3 v3 . (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context m, Show context) => MapReduce k1 v1 k3 v3 -> m ()
data DropException = DropException deriving (Show)
instance Exception DropException
type family Arg (c :: ClientType) = r | r -> c where
  Arg 'Single = ServiceName
  Arg 'Multi = (Int, ServiceName)

-- Class Worker 
-- specify the logic of how to run workers
class (Client t c, TaskRunner t r) => Worker (t :: StoreType) (c :: ClientType) (r :: TaskRunnerType) where
  runWorker :: forall k1 v1 k3 v3. (Serializable2 k1 v1, Serializable2 k3 v3) =>  MapReduce k1 v1 k3 v3 -> Arg c -> IO ()
instance (Client 'LocalFileStore c, TaskRunner 'LocalFileStore r) => Worker 'LocalFileStore (c :: ClientType) (r :: TaskRunnerType) where
    runWorker mr arg = (`runReaderT` (initialContext @Context)) $ runClient @'LocalFileStore @c (runTask @'LocalFileStore @r) mr arg
instance (Client 'RedisStore c, TaskRunner 'RedisStore r) => Worker 'RedisStore c r where
    runWorker mr args = do
        conn <- checkedConnect defaultConnectInfo
        void $ runRedis conn $ (`runReaderT` (initialContext @Context)) $ runClient @'RedisStore @c (runTask @'RedisStore @r) mr args  

-- Class Client
-- specify the logic of how to run clients,
-- it might be a single client or a multi client
class Client (t :: StoreType) (c :: ClientType) where
  runClient ::
    forall context m k1 v1 k3 v3 .
    (MonadStore t context m, MonadUnliftIO m) =>
    (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandlerM t context m->  MapReduce k1 v1 k3 v3 -> Arg c ->  m ()
instance Client (t :: StoreType) 'Single where
  runClient doTask mr port = do
    b <- catch (runClientWork @t doTask port mr)
      (\DropException -> logg "DropException" >> return True)
    when b $ runClient @t doTask mr port 
instance Client (t :: StoreType) 'Multi where
  runClient doWork mr (n, port) = mapConcurrently_ (flip (runClient @t doWork) port) (replicate n mr)

-- Class TaskRunner
-- specify how to run a single task
data TaskRunnerType = Normal | Drop | Delay deriving (Show)
class TaskRunner (t :: StoreType) (c :: TaskRunnerType) where
  runTask :: TaskHandlerM t context m

instance TaskRunner (t :: StoreType) 'Normal where
  runTask = doTask @t 
instance TaskRunner (t :: StoreType) 'Drop where
  runTask m = do
    i :: Int <- randomRIO (1,10)
    logg "dropping task" 
    if i > 5 then logg "not dropping" >> doTask @t m
    else throwIO DropException
instance TaskRunner (t :: StoreType) 'Delay where
  -- runTask = runTaskLocalWithDelay @t 1000000
  runTask mr = liftIO (threadDelay 10000) >> (doTask @t) mr 

-- >>> 1 + 1
runClientWork  ::
  forall (t :: StoreType) context m k1 v1 k3 v3.
  (Binary context, MonadStore t context m, Serializable2 k1 v1, Serializable2 k3 v3, Show context, MonadIO m, MonadUnliftIO m) =>
  TaskHandlerM t context m -> ServiceName -> MapReduce k1 v1 k3 v3 -> m Bool
runClientWork runT port mr =
  runTCPClient "127.0.0.1" port $ \s -> do
  -- logg "getting"
  msg <- liftIO $ recv s 10240
  -- get the work
  let t = decode msg
  setContext t $ do
    liftIO $ print t
    -- do the work for 1 second
    -- _ <- threadDelay 1000000
    if validWork @context t
      -- run the state here
      then runT mr >> liftIO (sendAll s (encode t)) >> return True
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