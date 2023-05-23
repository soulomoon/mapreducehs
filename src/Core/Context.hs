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
import Control.Monad.Reader (withReader)


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
  incrTaskId :: m a -> m a
  setContext :: context -> m a -> m a
  getContext :: m context



instance (Monad m, MonadReader Context m, MonadIO m) => MonadContext Context m where
  workerCount = asks _workerCountL
  partitionId = asks _partitionIdL
  taskId = asks _taskIdL
  spaceName = asks _spaceNameL
  dirName = asks _dirNameL
  -- incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})
  incrTaskId = local (\x -> x {_taskIdL = _taskIdL x + 1})
  getContext = ask
  setContext ctx = local (const ctx)

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

instance (Monad m, MonadReader (Context, Map String String) m, MonadIO m) => MonadContext (Context, Map String String) m where
  workerCount = asks (_workerCountL . fst)
  partitionId = asks (_partitionIdL .fst)
  taskId = asks (_taskIdL. fst)
  spaceName = asks (_spaceNameL.fst)
  dirName = asks (_dirNameL.fst)
  incrTaskId = local (\(x, y) -> (x {_taskIdL = _taskIdL x + 1}, y))
  getContext = ask
  setContext ctx = local (const ctx)


-- instance (Monad m, MonadState Context m, MonadIO m) => MonadContext 'RedisStore Context m where
--   workerCount = asks _workerCountL
--   partitionId = asks _partitionIdL
--   taskId = asks _taskIdL
--   spaceName = asks _spaceNameL
--   dirName = asks _dirNameL
--   incrTaskId = modify (\x -> x {_taskIdL = _taskIdL x + 1})
--   validWork = (>= 0) . _taskIdL 
--   getContext = get
--   invalidContext = Context (-1) (-1) "task" "tempdata" (-1)
--   genContext nWorker pipLineLength = [[Context nWorker tid "task" "tempdata" wid  | wid <- [0 .. nWorker-1] ] | tid <- [0 .. pipLineLength-1]]


-- -- makeLenses ''Context
