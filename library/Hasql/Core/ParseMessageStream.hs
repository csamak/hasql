module Hasql.Core.ParseMessageStream where

import Hasql.Prelude hiding (error)
import Hasql.Core.Model hiding (Error(..))
import qualified Hasql.Looping as B
import qualified Hasql.Core.ParseMessage as A
import qualified Hasql.Core.ParseDataRow as F
import qualified Hasql.Core.MessageTypePredicates as G
import qualified Hasql.Protocol.Decoding as E
import qualified Hasql.Protocol.Model as C
import qualified BinaryParser as D


{-|
A specification of how to parse a stream of messages.
-}
newtype ParseMessageStream result =
  ParseMessageStream (B.Looping A.ParseMessage result)
  deriving (Functor, Applicative, Alternative, Monad, MonadPlus)


parseMessage :: A.ParseMessage result -> ParseMessageStream result
parseMessage parseMessage =
  ParseMessageStream (B.Looping (fmap Left parseMessage))

error :: ParseMessageStream ErrorMessage
error =
  parseMessage A.error

errorCont :: (ByteString -> ByteString -> result) -> ParseMessageStream result
errorCont message =
  parseMessage (A.errorCont message)

commandComplete :: ParseMessageStream Int
commandComplete =
  parseMessage A.commandComplete

rows :: F.ParseDataRow row -> Fold row result -> ParseMessageStream result
rows parseDataRow (Fold foldStep foldStart foldEnd) =
  ParseMessageStream (fold foldStart)
  where
    fold !state =
      B.Looping (step <|> end)
      where
        step =
          fmap (Right . fold . foldStep state) (A.dataRow parseDataRow)
        end =
          (A.commandCompleteWithoutAmount <|> A.emptyQuery) $>
          Left (foldEnd state)

rowsAffected :: ParseMessageStream Int
rowsAffected =
  ParseMessageStream looping
  where
    looping =
      B.Looping (commandComplete <|> dataRow <|> emptyQuery)
      where
        commandComplete =
          Left <$> A.commandComplete
        dataRow =
          Right looping <$ A.dataRowWithoutData
        emptyQuery =
          Left 0 <$ A.emptyQuery

parseComplete :: ParseMessageStream ()
parseComplete =
  parseMessage A.parseComplete

bindComplete :: ParseMessageStream ()
bindComplete =
  parseMessage A.bindComplete

readyForQuery :: ParseMessageStream ()
readyForQuery =
  parseMessage A.readyForQuery

authentication :: ParseMessageStream (Either Text AuthenticationResult)
authentication =
  ParseMessageStream (iterate (Left "Missing the \"integer_datetimes\" setting"))
  where
    iterate !state =
      B.Looping (param <|> authentication)
      where
        param =
          fromParsingResult <$> A.parameterStatus
          where
            fromParsingResult (name, value) =
              case name of
                "integer_datetimes" -> case value of
                  "on" -> Right (iterate (Right True))
                  "off" -> Right (iterate (Right False))
                  _ -> Right (iterate (Left ("Unexpected value of the \"integer_datetimes\" setting: " <> (fromString . show) value)))
                _ -> Right (iterate state)
        authentication =
          fromParsingResult <$> A.authentication
          where
            fromParsingResult =
              \case
                C.OkAuthenticationMessage -> Left (fmap OkAuthenticationResult state)
                C.ClearTextPasswordAuthenticationMessage -> Left (Right NeedClearTextPasswordAuthenticationResult)
                C.MD5PasswordAuthenticationMessage salt -> Left (Right (NeedMD5PasswordAuthenticationResult salt))
