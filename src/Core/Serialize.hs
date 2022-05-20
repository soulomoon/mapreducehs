{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.Serialize where

import Data.Hashable

class Serializable a where
  serialize :: a -> String
  unSerialize :: String -> a

instance (Show a, Read a) => Serializable a where
  serialize = show
  unSerialize = read

type Serializable2 k v = (Show k, Show v, Read k, Read v, Ord k, Hashable k)
