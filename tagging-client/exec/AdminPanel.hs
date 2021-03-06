module Main where

import Data.Proxy
import Reflex
import Reflex.Dom
import Tagging.User
import Tagging.Stimulus
import Tagging.Response
import Tagging.Crud
import Reflex.Dom.Contrib.Widgets.ButtonGroup

main = mainWidget $ do
  el "hr" $ return ()

  el "hr" $ return ()
  text "TaggingUser Table"
  crudTableWidget (Proxy :: Proxy TaggingUser) (constDyn (const True))
  el "br" $ return ()

  el "hr" $ return ()
  text "Assignment Table"
  crudTableWidget (Proxy :: Proxy Assignment) (constDyn (const True))
  el "br" $ return ()

  el "hr" $ return ()
  text "StimulusSequence Table"
  crudTableWidget (Proxy :: Proxy StimulusSequence) (constDyn (const True))
  el "br" $ return ()

  -- el "hr" $ return ()
  -- text "StimSeqItem Table"
  -- crudTableWidget (Proxy :: Proxy StimSeqItem) (constDyn (const True))
  -- el "br" $ return ()

  -- el "hr" $ return ()
  -- text "StimulusRequest Table"
  -- crudTableWidget (Proxy :: Proxy StimulusRequest) (constDyn (const True))
  -- el "br" $ return ()

  -- el "hr" $ return ()
  -- text "StimulusResponse Table"
  -- crudTableWidget (Proxy :: Proxy StimulusResponse) (constDyn (const True))
  -- el "br" $ return ()

  return ()
