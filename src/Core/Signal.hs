{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}
module Core.Signal where


import Control.Concurrent
import Control.Monad.RWS
import Core.Context

class (Monad m) => MonadSignal m where
  signalIn ::  m (MVar ())
  signalOut ::  m (MVar ())
  taskChan :: m (Chan Context)
  askTask :: m Context
  wait :: m ()
  done :: m ()

instance (Monad m, MonadReader Signals m, MonadIO m) => MonadSignal m where
  signalIn = asks _signalIn
  signalOut = asks _signalOut
  taskChan = asks _taskChan
  wait = getSignal =<< signalIn
  done = putSignal =<< signalOut
  askTask = do 
    chan <- taskChan 
    liftIO $ readChan chan


getSignal :: MonadIO m => MVar a -> m a
getSignal sig = liftIO $ takeMVar sig
putSignal :: MonadIO m => MVar () -> m ()
putSignal sig = liftIO $ putMVar sig ()

data Signals = Signals
  { 
    _signalIn :: MVar (),
    _signalOut :: MVar (),
    _taskChan :: Chan Context
  }
  deriving (Show)

instance Show (MVar ()) where show _ = "()"
instance Show (Chan Context) where show _ = "()"

-- makeLenses ''Context