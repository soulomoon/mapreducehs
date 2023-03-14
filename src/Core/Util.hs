{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module Core.Util where

import Data.Map hiding (map)
import Data.Type.Equality 
import Data.Type.Bool

fromMap :: Ord k => Map k [a] -> [(k, a)]
fromMap = foldMapWithKey (\k xs -> map (k,) xs)

toMap :: Ord k => [(k, v)] -> Map k [v]
toMap = fromListWith (++) . map (fmap return)

type family Composed f g where
  Composed (a -> b) (c -> a) = c -> b
  Composed (a -> b) (c -> a1 -> b1) = c -> Composed (a -> b) (a1 -> b1)

class Composable f g
  where comp :: f -> g -> Composed f g

instance (Composable (a -> b) (a1 -> b1), (a == (a1 -> b1)) ~ 'False, Composed (a -> b) (c -> a1 -> b1) ~ (c -> Composed (a -> b) (a1 -> b1))) => Composable (a -> b) (c -> a1 -> b1)
  where comp f g = comp f . g

instance {-# OVERLAPPING #-} Composable (a -> b) (c -> a)
  where comp = (.)

-- >>> comp (+1) (+2) 3
-- Couldn't match type `Integer' with `()'
--   arising from a use of `it_a8Q6I'
-- In the first argument of `evalPrint', namely `it_a8Q6I'
-- In a stmt of an interactive GHCi command: evalPrint it_a8Q6I
