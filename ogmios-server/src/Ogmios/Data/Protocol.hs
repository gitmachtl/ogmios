--  This Source Code Form is subject to the terms of the Mozilla Public
--  License, v. 2.0. If a copy of the MPL was not distributed with this
--  file, You can obtain one at http://mozilla.org/MPL/2.0/.

module Ogmios.Data.Protocol
    ( MethodName
    , onUnmatchedMessage
    ) where

import Relude

import Relude.Extra.Map
    ( lookup )

import qualified Codec.Json.Wsp as Wsp
import qualified Codec.Json.Wsp.Handler as Wsp
import qualified Data.Aeson as Json
import qualified Data.Aeson.Types as Json
import qualified Data.Text as T

type instance Wsp.ServiceName (Wsp.Response _) = "ogmios"

type MethodName = String

-- | A default handler for unmatched requests. This is an attempt to provide
-- better error messages without adding too much complexity to the above
-- handlers.
--
-- Each handler is rather isolated and independent. They aren't aware of other
-- handlers and this makes them easy to extend or modify independently. A direct
-- consequence if that, from a single handler it is hard to tell whether a
-- request is totally invalid in the context of Ogmios, or simply invalid for
-- that particular handler.
--
-- When a handler fails to parse a request, it simply passes it to the next
-- handler in the pipeline. Ultimately, once all handlers have passed, we end up
-- with a request that wasn't proceeded successfully but, the reason why that is
-- are unclear at this stage:
--
-- - Is the request just a gibberish input?
-- - Is the request an almost valid 'FindIntersect' but with an error on the
--   argument?
-- - Is the request an almost valid 'SubmitTx' but with a slightly invalid
--   transaction body?
--
-- This is what this function tries to answer and yield back to users. To some
-- extent, it redoes some of the parsing work above, but it only occurs on
-- client errors. This way, base handlers are kept clean and fast for normal
-- processing.
onUnmatchedMessage
    :: (MethodName -> Json.Value -> Json.Parser Void)
    -> ByteString
    -> Json.Encoding
onUnmatchedMessage match blob = do
    Json.toEncoding $ Wsp.clientFault $ T.unpack fault
  where
    fault =
        "Invalid request: " <> modifyAesonFailure details <> "."
      where
        details = case Json.decode' (fromStrict blob) of
            Just (Json.Object obj) ->
                either toText absurd $ Json.parseEither userFriendlyParser obj
            _ ->
                "must be a well-formed JSON object."

    modifyAesonFailure :: Text -> Text
    modifyAesonFailure
        = T.dropWhileEnd (== '.')
        . T.replace "Error in $["    "invalid item ["
        . T.replace "Error in $: "    ""
        . T.replace "Error in $: key" "field"

    -- A parser that never resolves, yet yield proper error messages based on
    -- the attempted request.
    userFriendlyParser :: Json.Object -> Json.Parser Void
    userFriendlyParser obj = do
        methodName <-
            case lookup "methodname" obj of
                Just (Json.String t) -> pure (T.unpack t)
                _ -> fail "field 'methodname' must be present and be a string."
        match methodName (Json.Object obj)


-- --
-- -- Error Handling
-- --
--
-- -- | Default handler attempting to provide user-friendly error message. See also
-- -- 'Ogmios.Data.Protocol#onUnmatchedMessage'.
-- --
-- -- NOTE: This function is ambiguous in 'block' and requires a type application.
-- parserVoid
--     :: forall block. (FromJSON (Point block))
--     => MethodName
--     -> Json.Value
--     -> Json.Parser Void
-- parserVoid methodName json = do
--     if | methodName == Wsp.gWSPMethodName (Proxy @(Rep (FindIntersect block) _)) ->
--             void $ parseJSON @(Wsp.Request (FindIntersect block)) json
--        | methodName == Wsp.gWSPMethodName (Proxy @(Rep RequestNext _)) ->
--             void $ parseJSON @(Wsp.Request RequestNext) json
--        | otherwise ->
--             pure ()
--
--     fail "unknown method in 'methodname' (beware names are case-sensitive). \
--          \Expected either: 'FindIntersect' or 'RequestNext'."
--
--
-- Error Handling
--

-- -- | Default handler attempting to provide user-friendly error message. See also
-- -- 'Ogmios.Data.Protocol#onUnmatchedMessage'.
-- --
-- -- NOTE: This function is ambiguous in 'block' and requires a type application.
-- parserVoid
--     :: forall block.
--         ( FromJSON (SomeQuery Maybe Json.Value block)
--         , FromJSON (Point block)
--         )
--     => MethodName
--     -> Json.Value
--     -> Json.Parser Void
-- parserVoid methodName json = do
--     if | methodName == Wsp.gWSPMethodName (Proxy @(Rep (Acquire block) _)) ->
--             void $ parseJSON @(Wsp.Request (Acquire block)) json
--        | methodName == Wsp.gWSPMethodName (Proxy @(Rep Release _)) ->
--             void $ parseJSON @(Wsp.Request Release) json
--        | methodName == Wsp.gWSPMethodName (Proxy @(Rep (Query Json.Value block) _)) ->
--             void $ parseJSON @(Wsp.Request (Query Json.Value block)) json
--        | otherwise ->
--           pure ()
--
--     fail "unknown method in 'methodname' (beware names are case-sensitive). \
--          \Expected one of: 'Acquire', 'Release' or 'Query'."
--
--
-- --
-- -- Error Handling
-- --
--
-- -- | Default handler attempting to provide user-friendly error message. See also
-- -- 'Ogmios.Data.Protocol#onUnmatchedMessage'.
-- --
-- -- NOTE: This function is ambiguous in 'tx' and requires a type application.
-- parserVoid
--     :: forall tx. (FromJSON tx)
--     => MethodName
--     -> Json.Value
--     -> Json.Parser Void
-- parserVoid methodName json = do
--     if methodName == Wsp.gWSPMethodName (Proxy @(Rep (SubmitTx tx) _)) then
--         void $ parseJSON @(Wsp.Request (SubmitTx tx)) json
--     else
--         pure ()
--
--     fail "unknown method in 'methodname' (beware names are case-sensitive). \
--          \Expected: 'SubmitTx'."