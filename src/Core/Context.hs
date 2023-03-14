{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeApplications #-}

module Core.Context where

import Control.Monad.RWS
import Core.Type (Context(..))
import Data.Map (Map, empty)
import Data.Binary (Binary)


class (Binary context, Show context, Eq context) => IsContext context where
  validWork :: context -> Bool
  invalidContext :: context
  genContext :: Int -> Int -> [[context]]
  initialContext :: context
  finalContext :: Int -> context

class (Monad m, Binary context, Show context, Eq context, IsContext context) => MonadContext context m where
  workerCount :: m Int
  partitionId :: m Int
  spaceName :: m String
  dirName :: m String
  taskId :: m Int
  incrTaskId :: m ()
  setContext :: context -> m ()
  getContext :: m context



instance (Monad m, MonadState Context m, MonadIO m) => MonadContext Context m where
  workerCount = gets _workerCountL
  partitionId = gets _partitionIdL
  taskId = gets _taskIdL
  spaceName = gets _spaceNameL
  dirName = gets _dirNameL
  incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})
  getContext = get
  setContext = put

instance IsContext Context where
  validWork = (>= 0) . _taskIdL 
  invalidContext = Context (-1) (-1) "task" "tempdata" (-1)
  genContext nWorker pipLineLength = [[Context nWorker tid "task" "tempdata" wid  | wid <- [0 .. nWorker-1] ] | tid <- [0 .. pipLineLength-1]]
  initialContext = Context 5 0 "task" "tempdata" 0
  finalContext n = Context 5 n "task" "tempdata" 0

instance IsContext (Context, Map String String) where
  validWork = (>= 0) . _taskIdL . fst
  invalidContext = (Context (-1) (-1) "task" "tempdata" (-1), mempty)
  genContext nWorker pipLineLength = [[ (x,empty) | x <- c] | c <- genContext @Context nWorker pipLineLength]
  initialContext = (Context 5 0 "task" "tempdata" 0, empty)
  finalContext n = (Context 5 n "task" "tempdata" 0, empty)

instance (Monad m, MonadState  (Context, Map String String) m, MonadIO m) => MonadContext (Context, Map String String) m where
  workerCount = gets (_workerCountL . fst)
  partitionId = gets (_partitionIdL .fst)
  taskId = gets (_taskIdL. fst)
  spaceName = gets (_spaceNameL.fst)
  dirName = gets (_dirNameL.fst)
  incrTaskId = modify (\(x, y) -> (x {_taskIdL = _taskIdL x + 1}, y))
  setContext = put
  getContext = get


-- instance (Monad m, MonadState Context m, MonadIO m) => MonadContext 'RedisStore Context m where
--   workerCount = gets _workerCountL
--   partitionId = gets _partitionIdL
--   taskId = gets _taskIdL
--   spaceName = gets _spaceNameL
--   dirName = gets _dirNameL
--   incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})
--   validWork = (>= 0) . _taskIdL 
--   getContext = get
--   invalidContext = Context (-1) (-1) "task" "tempdata" (-1)
--   genContext nWorker pipLineLength = [[Context nWorker tid "task" "tempdata" wid  | wid <- [0 .. nWorker-1] ] | tid <- [0 .. pipLineLength-1]]


-- -- makeLenses ''Context
