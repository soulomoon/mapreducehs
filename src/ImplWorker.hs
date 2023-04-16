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
import Core.Std
import Core.Type (StoreType(LocalFileStore, RedisStore))
import Core.Logging
import UnliftIO.Async (mapConcurrently_)
import Control.Monad.State
import System.Random (randomRIO)
import Control.Concurrent (threadDelay)
import Core.Context(validWork)
import UnliftIO (MonadUnliftIO, Exception, catch, throwIO, bracket)
import Database.Redis (checkedConnect, defaultConnectInfo, runRedis)


data ClientType = Single | SingleDelay | Multi deriving (Show)
type TaskHandlerM (t :: StoreType) context m =  forall k1 v1 k3 v3 . (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore t context (StateT context m), Show context) => MapReduce k1 v1 k3 v3 -> context -> m ()
data DropException = DropException deriving (Show)
instance Exception DropException
-- type family Arg (c :: ClientType) :: *
type family Arg (c :: ClientType) 
type instance Arg 'Single = ServiceName
type instance Arg 'Multi = (Int, ServiceName)

class (Client t c, TaskRunner t r) => Worker (t :: StoreType) (c :: ClientType) (r :: TaskRunnerType) where
  runWorker :: forall k1 v1 k3 v3 . (Serializable2 k1 v1, Serializable2 k3 v3) =>  MapReduce k1 v1 k3 v3 -> Arg c ->  IO ()

instance (Client 'LocalFileStore c, TaskRunner 'LocalFileStore r) => Worker 'LocalFileStore (c :: ClientType) (r :: TaskRunnerType) where
    runWorker = runClient @'LocalFileStore @c (runTask @'LocalFileStore @r)

instance (Client 'RedisStore c, TaskRunner 'RedisStore r) => Worker 'RedisStore c r where
    runWorker mr args = do
        conn <- checkedConnect defaultConnectInfo
        void $ runRedis conn $ runClient @'RedisStore @c (runTask @'RedisStore @r) mr args  

class Client (t :: StoreType) (c :: ClientType) where
  runClient ::
    forall context m k1 v1 k3 v3 .
    (MonadStore t context (StateT context m), Show context, Monad m, MonadIO m, MonadUnliftIO m) =>
    (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandlerM t context m->  MapReduce k1 v1 k3 v3 -> Arg c ->  m ()

instance Client (t :: StoreType) 'Single where
  runClient ::
    forall context m k1 v1 k3 v3 .
    (MonadStore t context (StateT context m), Show context, Monad m, MonadIO m, MonadUnliftIO m) =>
    (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandlerM t context m->  MapReduce k1 v1 k3 v3 -> Arg 'Single ->  m ()
  runClient doWork mr port = do
    b <- catch (runClientWork @t @context @m doWork port mr)
      (\DropException -> logg "DropException" >> return True)
    when b $ runClient @t @'Single @context doWork mr port 

instance Client (t :: StoreType) 'Multi where
  runClient doWork mr (n, port) = mapConcurrently_ (flip (runClient @t @'Single doWork) port) (replicate n mr)

data TaskRunnerType = Normal | Drop | Delay deriving (Show)
class TaskRunner (t :: StoreType) (c :: TaskRunnerType) where
  runTask :: forall context m k1 v1 k3 v3 . 
    (MonadStore t context (StateT context m)
    , Show context, Monad m, MonadIO m, MonadUnliftIO m
    , Serializable2 k1 v1, Serializable2 k3 v3
    ) 
    => MapReduce k1 v1 k3 v3 -> context -> m ()

instance TaskRunner (t :: StoreType) 'Normal where
  runTask = runTaskM @t

instance TaskRunner (t :: StoreType) 'Drop where
  runTask m n = do
    i :: Int <- randomRIO (1,10)
    logg $ "dropping task" ++ show n
    if i > 5 then logg "not dropping" >> runTaskM @t m n
    else throwIO DropException

instance TaskRunner (t :: StoreType) 'Delay where
  -- runTask = runTaskLocalWithDelay @t 1000000
  runTask mr ctx = liftIO (threadDelay 10000) >> (runTaskM @t) mr ctx

-- runTaskLocalWithDelay ::
--   forall (t :: StoreType) context m.
--   (MonadStore t context (StateT context m), Monad m, MonadIO m) =>
--   Int -> TaskHandlerM t context m
-- runTaskLocalWithDelay dt m n = liftIO (threadDelay dt) >> (runTaskM @t) m n



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