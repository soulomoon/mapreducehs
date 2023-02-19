module Impl where

import Core.MapReduceC
import Core.Context
import Data.List

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

-- generate a list of context, each context is a task in the pipeline
genContext :: Int -> MapReduce k1 v1 k3 v3 -> [[Context]]
genContext nWorker mr =
  let k = pipeLineLength mr in
  [[Context nWorker tid "task" "tempdata" wid  | wid <- [0 .. nWorker-1] ] | tid <- [0 .. k-1]]
