{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.Worker where
import Core.MapReduceC
import Core.Context
import Core.Serialize
import Core.Partition (PartitionConstraint, sendDataToPartitions, getDataFromPartition)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State
import Control.Monad.Reader (ReaderT (runReaderT), MonadReader)



-- evaluator extension
evId :: forall m k v. (Serializable2 k v, MonadContext m, Monad m) => Trans m k v
evId ev ev' e = incrTaskId >> ev ev' e


    

    


