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

import Core.Context
import Core.MapReduceC
import Core.Partition
import Control.Monad.State

-- should increase id before send
evalOne :: (PartitionConstraint m) => EvalPair -> m ()
evalOne (EvalPair mr d) = incrTaskId >> sendDataToPartitions (mr d)

runCtx:: Monad m => Context -> (StateT Context m) a -> m a
runCtx context =  (`evalStateT` context)