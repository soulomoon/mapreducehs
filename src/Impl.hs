module Impl where

import Core.MapReduceC
import Core.Context
import Data.List
import Control.Monad.State (evalStateT, StateT)

mapper :: (String, String) -> [(Char, Int)]
mapper (_, v) = map (\xs -> (head xs, length xs)) $ group v

mapperAdd1 :: (Char, Int) -> [(Char, Int)]
mapperAdd1 (k, v) = [(k, v + 1)]

reducer :: Char -> [Int] -> [Int]
reducer _ xs = [sum xs]

sample :: [([Char], [Char])]
sample = [("", "hello")]
--     sample
-- sampleReduce :: MapReduce k1 v1 k3 v3
sampleReduce :: MapReduce [Char] [Char] Char Int
sampleReduce = MrOut :> toM reducer :> toM mapperAdd1 :> toM mapper

getContext :: Int -> MapReduce k1 v1 k3 v3 -> [[Context]]
getContext n mr =
  let k = pipeLineLength mr in
  [[Context n tid "task" "tempdata" wid  | wid <- [0 .. n-1] ] | tid <- [0 .. k-1]]

runCtx:: Monad m => Context -> (StateT Context m) a -> m a
runCtx context =  (`evalStateT` context)