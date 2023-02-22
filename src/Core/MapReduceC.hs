{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Core.MapReduceC where

import Core.Serialize
import Core.Util
import qualified Data.Map as Map

-- unify the map and reduce for now, would recognize them later
type MR k1 v1 k2 v2 = [(k1, v1)] -> [(k2, v2)]

type Mapper k1 v1 k2 v2 = (k1, v1) -> [(k2, v2)]

type Reducer k1 v1 v2 = k1 -> [v1] -> [v2]

class ToM a b | a -> b where
  toM :: a -> b

instance (Ord k1, Ord k2) => ToM (Mapper k1 v1 k2 v2) (MR k1 v1 k2 v2) where
  -- toM :: (Ord k1, Ord k2) => Mapper k1 v1 k2 v2 -> MapReduce k1 v1 k2 v2
  toM s = concatMap s

instance (Ord k1) => ToM (Reducer k1 v1 v2) (MR k1 v1 k1 v2) where
  -- toM :: Ord k1 => Reducer k1 v1 v2 -> MapReduce k1 v1 k1 v2
  toM f = fromMap . reduceWith f . toMap
    where
      reduceWith :: Reducer k a b -> Map.Map k [a] -> Map.Map k [b]
      reduceWith = Map.mapWithKey

data MapReduce k1 v1 k3 v3 where
  (:>) :: (Serializable2 k2 v2) => MapReduce k2 v2 k3 v3 -> MR k1 v1 k2 v2 -> MapReduce k1 v1 k3 v3
  MrOut :: (k1 ~ k3, v1 ~ v3) => MapReduce k1 v1 k3 v3

-- existing an input
data E k3 v3 = forall k2 v2. (Serializable2 k2 v2) => E [(k2, v2)] (MapReduce k2 v2 k3 v3)


-- provide inject point through ev
evaluateF :: (Monad m, Serializable2 k v) => (Evaluator m k v -> Evaluator m k v)
evaluateF ev mr = do
  case evaluateOne mr of
    Right x -> return x
    Left x -> ev x

type Evaluator m k3 v3 = E k3 v3 -> m [(k3, v3)]

type Trans m k v = (Evaluator m k v -> Evaluator m k v) -> (Evaluator m k v -> Evaluator m k v)

-- fix up recursion on evaluator
fixM :: (Evaluator m k v -> Evaluator m k v) -> Evaluator m k v
fixM ev = ev (fixM ev)

naiveEvaluator :: (Monad m, Serializable2 k3 v3, Serializable2 k1 v1) => [(k1, v1)] -> MapReduce k1 v1 k3 v3 -> m [(k3, v3)]
naiveEvaluator d action = naiveEvaluator' (E d action)

naiveEvaluator' :: (Monad m, Serializable2 k v) => Evaluator m k v
naiveEvaluator' = fixM evaluateF

-- small step evaluation
evaluateOne :: E k3 v3 -> Either (E k3 v3) [(k3, v3)]
evaluateOne (E x MrOut) = Right x
evaluateOne (E x (g :> f)) = Left $ E (f x) g

-- index into some part of the map reduce
indexMapReduce ::
  (Serializable2 k1 v1, Monad m) =>
  -- | index into the map reduce
  Int ->
  -- | the map reduce operation chain
  MapReduce k1 v1 k3 v3 ->
  (forall k v. (Serializable2 k v) => m [(k, v)]) ->
  m (E k3 v3) -- the temporal map reduce state
indexMapReduce 0 f s = flip E f <$> s
indexMapReduce n (g :> _) s = indexMapReduce (n -1) g s
indexMapReduce _ _ _ = error "index out of bounds"

-- index into some part of the map reduce
indexMR ::
  (Serializable2 k1 v1, Monad m) =>
  -- | index into the map reduce
  Int ->
  -- | the map reduce operation chain
  MapReduce k1 v1 k3 v3 ->
  (forall k v. (Serializable2 k v) => m [(k, v)]) ->
  m (Maybe EvalPair) -- the temporal map reduce state
indexMR 0 (_ :> f) s = Just <$> (EvalPair f <$> s)
indexMR n (g :> _) s = indexMR (n-1) g s
indexMR _ _ _ = return Nothing

pipeLineLength :: MapReduce k1 v1 k3 v3 -> Int
pipeLineLength MrOut = 0
pipeLineLength (f :> _) = 1 + pipeLineLength f

data EvalPair = forall k2 v2 k3 v3. (Serializable2 k2 v2, Serializable2 k3 v3) => EvalPair (MR k2 v2 k3 v3) [(k2, v2)]

