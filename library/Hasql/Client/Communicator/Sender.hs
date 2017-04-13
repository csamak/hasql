module Hasql.Client.Communicator.Sender where

import Hasql.Prelude
import qualified Hasql.Client.Socket as F
import qualified Hasql.Buffer as E
import qualified ByteString.StrictBuilder as D


data Sender =
  Sender F.Socket E.Buffer

acquire :: F.Socket -> IO Sender
acquire socket =
  Sender socket <$> E.new (shiftL 1 15)

schedule :: Sender -> D.Builder -> IO ()
schedule (Sender _ buffer) builder =
  D.builderPtrFiller builder $ \size ptrFiller -> do
    E.put buffer size $ \ptr -> do
      ptrFiller ptr
      return ((), size)

flush :: Sender -> IO (Either Text ())
flush (Sender socket buffer) =
  E.take buffer $ \ptr amount -> do
    sendResult <- F.sendFromPtr socket ptr amount
    case sendResult of
      Right takenAmount ->
        return (Right (), takenAmount)
      Left error -> 
        return (Left error, 0)
