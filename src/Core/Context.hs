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
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module Core.Context where

import Control.Monad.RWS
import Data.Binary (Binary)
import GHC.Generics (Generic)
import Core.Type (StoreType (LocalFileStore, MemoryStore), Context(..))
import Data.Map (Map)

class (Monad m) => MonadContext (t :: StoreType) m where
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

instance (Monad m, MonadState Context m, MonadIO m) => MonadContext 'LocalFileStore m where
  workerCount = gets _workerCountL
  partitionId = gets _partitionIdL
  taskId = gets _taskIdL
  spaceName = gets _spaceNameL
  dirName = gets _dirNameL
  incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})

instance (Monad m, MonadState (Context, Map String String) m, MonadIO m) => MonadContext 'MemoryStore m where
  workerCount = gets (_workerCountL . fst)
  partitionId = gets (_partitionIdL .fst)
  taskId = gets (_taskIdL. fst)
  spaceName = gets (_spaceNameL.fst)
  dirName = gets (_dirNameL.fst)
  incrTaskId = modify (\(x, y) -> (x {_taskIdL = _taskIdL x + 1}, y))




-- makeLenses ''Context
