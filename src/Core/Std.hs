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

-- should increase id before send
evalOne :: (PartitionConstraint m) => EvalPair -> m ()
evalOne (EvalPair mr d) = incrTaskId >> sendDataToPartitions (mr d)