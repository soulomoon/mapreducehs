module Core.Type where

data EvaluateType
  = LocalSimple
  | LocalMultipleWorkers

data WorkerType = VirtualWorker | ActualWorker