{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.Std where

import Control.Applicative
import Control.Concurrent (MVar, forkIO, newEmptyMVar, newChan)
import Control.Monad.State
import Core.Context
import Core.MapReduceC
import Core.Partition
import Core.Serialize (Serializable2)
import Core.Type
import Control.Monad.Reader (ReaderT (runReaderT))

-- standard implementation of running the interpreter

-- main spawn virtual workers, each virtual workers invoke working on different real workers
-- real worker may die, virtual worker never dies.
-- 1. virtual worker spawn a new thread to timeout the virtual worker
-- 2. virtual worker send signal to worker to start working.
-- 3. virtual worker wait for the worker to response.

-- evaluator extension
evId :: forall m k v. (Serializable2 k v, MonadContext m, Monad m) => Trans m k v
evId ev ev' e = incrTaskId >> ev ev' e

runContext :: Monad m => Context -> StateT Context m a -> m a
runContext context =  (`evalStateT` context) 