{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Core.Context where

import Control.Monad.RWS
import Data.ByteString.Char8 (ByteString)
import Data.Binary (Binary)
import GHC.Generics (Generic)

class (Monad m) => MonadContext m where
  workerCount :: m Int
  partitionId :: m Int
  spaceName :: m String
  dirName :: m String
  taskId :: m Int
  incrTaskId :: m ()

class Has c m where
  getC :: m c

instance (MonadState Context m) => Has Context m where
  getC = get

instance (Monad m, MonadState Context m, MonadIO m) => MonadContext m where
  workerCount = gets _workerCountL
  partitionId = gets _partitionIdL
  taskId = gets _taskIdL
  spaceName = gets _spaceNameL
  dirName = gets _dirNameL
  incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})


data Context = Context { 
    _workerCountL :: Int,
    _taskIdL :: Int,
    _spaceNameL :: String,
    _dirNameL :: String,
    _partitionIdL :: Int
} deriving (Show, Generic, Binary, Eq)


-- makeLenses ''Context
