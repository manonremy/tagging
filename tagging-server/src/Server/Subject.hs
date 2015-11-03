{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Server.Subject where

import           Control.Error
import           Control.Lens
import           Control.Monad
import           Control.Monad.IO.Class     (liftIO)
import           Control.Monad.Trans.Class  (lift)
import           Control.Monad.Trans.Except (except)
import           Control.Monad.Logger       (NoLoggingT)
import qualified Data.ByteString.Char8      as B8
import qualified Data.List as L
import           Data.Proxy
import qualified Data.Text as T
import           Data.Time
import           Database.Groundhog
import           Database.Groundhog.Postgresql
import           Database.Groundhog.Postgresql.Array
import           GHC.Generics
import           GHC.Int
import           Servant
import           Servant.Docs
import           Servant.Server
import           Snap.Core
import           Snap.Snaplet
import           Snap.Snaplet.PostgresqlSimple
import qualified Data.Aeson as A

import           Tagging.Stimulus
import           Tagging.Response
import           Tagging.User
import           Server.Application
import           Server.Crud
import           Server.Database
import           Server.Resources
import           Server.Utils


------------------------------------------------------------------------------
type SubjectAPI = "currentstim" :> Get '[JSON] StimSeqItem
--             :<|> "sequence"    :> Get '[JSON] (Int64, StimulusSequence)
             :<|> "posinfo"     :> Get '[JSON] PositionInfo
             :<|> "response"    :> ReqBody '[JSON] ResponsePayload
                                :> Post '[JSON] ()


------------------------------------------------------------------------------
subjectServer :: Server SubjectAPI AppHandler
subjectServer = handleCurrentStimSeqItem :<|> handleCurrentPositionInfo :<|> response
  where -- resource   = getCurrentStimSeqItem
--        sequence   = lift $ getCurrentStimulusSequence
        pos        = getCurrentPositionInfo
        response v = handleSubmitResponse v

-- ------------------------------------------------------------------------------
-- -- | Add or revoke roles on a user
-- assignRoleTo :: AutoKey TaggingUser -> Role -> Bool -> Handler App App ()
-- assignRoleTo targetKey r b = exceptT Server.Utils.err300 (\_ -> return ()) $ do
--   lift $ assertRole [Admin]
--   tu <- noteT "Bad user lookup" $ MaybeT $ runGH $ get targetKey
--   let roles' = (if b then L.union [r] else L.delete r) $ tuRoles tu
--   lift $ runGH $ replace targetKey (tu {tuRoles = roles'})

-- handleAssignRoleTo :: Handler App App ()
-- handleAssignRoleTo = void $ runMaybeT $ do
--   userKey   <- return undefined -- TODO
--   theRole   <- MaybeT (getParam "role")
--   role      <- hoistMaybe (readMay $ B8.unpack theRole)
--   theUpDown <- MaybeT (getParam "bool")
--   upDown    <- hoistMaybe (readMay $ B8.unpack theUpDown)
--   lift $ assignRoleTo userKey role upDown


------------------------------------------------------------------------------
-- | Submit a response. Submission will update the user's current-stimulus
--   field to @Just@ `the next sequence stimulus` if there is one, or to
--   @Nothing@ if the sequence is done
--handleSubmitResponse :: StimulusResponse -> Handler App App ()
handleSubmitResponse :: ResponsePayload -> Handler App App ()
handleSubmitResponse t =
  exceptT Server.Utils.err300 (const $ return ()) $ do

    u        <- getCurrentTaggingUser
    pos      <- noteT "No assigned stimulus" $ hoistMaybe (tuCurrentStimulus u)
    let i = _piStimSeqIndex pos

    thisReq  <- noteT "No request record by user for stimulus"
                $ MaybeT $ fmap listToMaybe $ runGH
                $ select $ (SreqUserField ==. tuId u
                           &&. SreqStimSeqItemField ==. pos)
                           `orderBy` [Asc SreqTimeField]
    tNow     <- lift $ liftIO getCurrentTime

    stim     <- noteT "Bad stim lookup from response" $ MaybeT $ runGH
                $ get (intToKey (Proxy :: Proxy StimulusSequence)
                                (_piStimulusSequence pos))

    -- TODO: How to query the array length in groundhog?
    -- TODO This is definitely a (runtime) name error
    [Only l] <- lift $ with db $
           query
           "SELECT array_length(\"StimSeqItems\") FROM \"StimulusSequence\" WHERE id = ?"
           (Only (_piStimulusSequence pos))
    lift . runGH $ do
      insert (StimulusResponse (tuId u) pos
              (sreqTime thisReq) tNow "sometype" (rpJson t))
      let p' | i == l - 1 = Nothing
             | otherwise    = Just $ pos & over piStimSeqIndex succ
      update [TuCurrentStimulusField =. p'] (TuIdField ==. tuId u)


------------------------------------------------------------------------------
getCurrentPositionInfo :: AppHandler (Maybe PositionInfo)
getCurrentPositionInfo = exceptT Server.Utils.err300 return $ do
  u   <- getCurrentTaggingUser
  return (tuCurrentStimulus u)

handleCurrentPositionInfo :: AppHandler PositionInfo
handleCurrentPositionInfo =
  maybeT (Server.Utils.err300 "No stmilusus sequence assigned") return
  $ MaybeT getCurrentPositionInfo

getCurrentStimSeqItem :: AppHandler (Maybe StimSeqItem)
getCurrentStimSeqItem = do
  res <- getCurrentPositionInfo
  case res of
    Nothing -> error "NoUser" -- TODO
    Just pInfo@(PositionInfo key i) -> do
      u :: TaggingUser <- exceptT (const $ error "Bad lookup") return getCurrentTaggingUser
      t <- liftIO getCurrentTime
      modifyResponse $ Snap.Core.addHeader "Cache-Control" "no-cache"
      ssi <- with db $
                    query
                    "SELCET \"StimSeqItem[?]\" FROM \"StimulusSequence\" WHERE id=?"
                    (key, i)
      case ssi of
        [] -> return Nothing
        [Only ssi] -> do
          runGH $ insert (StimulusRequest (tuId u) pInfo t)
          return $ Just ssi
      -- runGH $ do
      --   r <- get $ intToKey (Proxy :: Proxy StimulusSequence) key
      --   case r of
      --     Nothing      -> error "Bad stimulussequence lookup" -- TODO better error
      --     Just stimSeq -> do
      --       -- ssi <- select $ SsItemsField ! i
      --       unless (null ssi) (void $ insert (StimulusRequest (tuId u) pInfo t))
      --       return (listToMaybe ssi)
      --       --case ssi of
      --       --  [ssi'] -> insert (StimulusRequest (tuId u) pInfo t) >> return ssi'
      --       --  _      -> error "Bad stim lookup"

handleCurrentStimSeqItem :: AppHandler StimSeqItem
handleCurrentStimSeqItem =
  maybeT (Server.Utils.err300 "No stmilusus sequence assigned") return
  $ MaybeT getCurrentStimSeqItem

