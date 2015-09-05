{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE TypeOperators         #-}

module Server.Subject where

import Control.Error
import Control.Monad
import Control.Monad.Trans.Class (lift)
import Control.Monad.Logger (NoLoggingT)
import qualified Data.ByteString.Char8 as B8
import qualified Data.List as L
import Data.Proxy
import Database.Groundhog
import Database.Groundhog.Postgresql (Postgresql)
import GHC.Int
import Servant
import Servant.Server
import Snap.Core
import Snap.Snaplet
import qualified Data.Aeson as A
import Snap.Snaplet.Groundhog.Postgresql

import Tagging.Stimulus
import Tagging.Response
import Tagging.User
import Server.Application
import Server.Crud
import Server.Resources
import Server.Utils


------------------------------------------------------------------------------
type SubjectAPI = "resource" :> Get '[JSON] StimulusResource
             :<|> "sequence" :> Get '[JSON] StimulusSequence
             :<|> "response" :> ReqBody '[JSON] StimulusResponse
                             :> Post '[JSON] ()


------------------------------------------------------------------------------
subjectServer :: Server (SubjectAPI) AppHandler
subjectServer = resource :<|> sequence :<|> response
  where resource   = lift $ getCurrentStimulusResource
        sequence   = lift $ getCurrentStimulusSequence
        response v = lift $ handleSubmitResponse v

------------------------------------------------------------------------------
-- | Add or revoke roles on a user
assignRoleTo :: AutoKey TaggingUser -> Role -> Bool -> Handler App App ()
assignRoleTo targetKey r b = eitherT Server.Utils.err300 (\_ -> return ()) $ do
  lift $ assertRole [Admin]
  tu <- noteT "Bad user lookup" $ MaybeT $ gh $ get targetKey
  let roles' = (if b then L.union [r] else L.delete r) $ tuRoles tu
  lift $ gh $ replace targetKey (tu {tuRoles = roles'})

handleAssignRoleTo :: Handler App App ()
handleAssignRoleTo = void $ runMaybeT $ do
  userKey   <- return undefined -- TODO
  theRole   <- MaybeT (getParam "role")
  role      <- hoistMaybe (readMay $ B8.unpack theRole)
  theUpDown <- MaybeT (getParam "bool")
  upDown    <- hoistMaybe (readMay $ B8.unpack theUpDown)
  lift $ assignRoleTo userKey role upDown


------------------------------------------------------------------------------
-- | Submit a response. Submission will update the user's current-stimulus
--   field to @Just@ `the next sequence stimulus` if there is one, or to
--   @Nothing@ if the sequence is done
handleSubmitResponse :: StimulusResponse -> Handler App App ()
handleSubmitResponse r@StimulusResponse{..} =
  eitherT Server.Utils.err300 (const $ return ()) $ do

    loggedInUser           <- getCurrentTaggingUser
    stim                   <- noteT "Bad stim lookup from response"
                              $ MaybeT $ gh $ get (intToKey Proxy srStim)
    respUser               <- lift $ crudGet (intToKey Proxy srUser)

    when (tuId loggedInUser /= tuId respUser)
      (lift $ Server.Utils.err300 "Logged in user / reported user mismatch")

    lift . gh $ do
      insert r
      insert (loggedInUser {tuCurrentStimulus = ssiNextItem stim})

------------------------------------------------------------------------------
getCurrentStimulusPosition :: EitherT String AppHandler StimSeqItem
getCurrentStimulusPosition = do
  loggedInUser <- getCurrentTaggingUser
  itemKey      <- noteT "No sequence assigned"
                  (hoistMaybe $ tuCurrentStimulus loggedInUser)
  ssi          <- noteT "Bad seq lookup" $ MaybeT $ gh $ get (intToKey Proxy itemKey)
  return ssi


------------------------------------------------------------------------------
getCurrentStimulusResource :: AppHandler StimulusResource
getCurrentStimulusResource = eitherT Server.Utils.err300 return $ do
  ssi <- getCurrentStimulusPosition
  noteT "Bad resource lookup" $ MaybeT $ gh $
    get (intToKey Proxy $ ssiStimulus ssi)


------------------------------------------------------------------------------
getCurrentStimulusSequence :: AppHandler StimulusSequence
getCurrentStimulusSequence = eitherT Server.Utils.err300 return $ do
  ssi <- getCurrentStimulusPosition
  noteT "Bad sequence lookup" $ MaybeT $ gh $
    get (intToKey Proxy $ ssiStimSeq ssi)
