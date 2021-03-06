{-# LANGUAGE RankNTypes #-}
module Data.Yaml.Include (decodeFile, decodeFileEither) where

import Control.Applicative
import Control.Monad (when)
import Control.Exception (throwIO)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Resource (MonadResource)
import System.Directory
import System.FilePath
import Data.Text (unpack)
import Data.Text.Encoding (decodeUtf8)
import Data.Aeson (FromJSON)
import Data.Conduit
import qualified Data.Conduit.List as CL
import Data.Yaml (ParseException(..), decodeHelper)
import Text.Libyaml hiding (decodeFile)
import qualified Text.Libyaml as Y

eventsFromFile
    :: MonadResource m
    => FilePath
    -> Producer m Event
eventsFromFile = go []
  where
    go :: MonadResource m => [FilePath] -> FilePath -> Producer m Event
    go seen fp = do
        cfp <- liftIO $ canonicalizePath fp
        when (cfp `elem` seen) $ do
            liftIO $ throwIO CyclicIncludes
        Y.decodeFile cfp $= do
            awaitForever $ \event -> case event of
                EventScalar f (UriTag "!include") _ _ -> do
                    let includeFile = takeDirectory cfp </> unpack (decodeUtf8 f)
                    go (cfp : seen) includeFile $= CL.filter (`notElem` irrelevantEvents)
                _ -> yield event

    irrelevantEvents = [EventStreamStart, EventDocumentStart, EventDocumentEnd, EventStreamEnd]

-- | Like `Data.Yaml.decodeFile` but with support for relative and absolute
-- includes.
--
-- The syntax for includes follows the form:
--
-- > somekey: !include ./somefile.yaml
decodeFile
    :: FromJSON a
    => FilePath
    -> IO (Maybe a)
decodeFile fp = decodeHelper (eventsFromFile fp) >>= either throwIO (return . either (const Nothing) id)

-- | Like `Data.Yaml.decodeFileEither` but with support for relative and
-- absolute includes.
--
-- The syntax for includes follows the form:
--
-- > somekey: !include ./somefile.yaml
decodeFileEither
    :: FromJSON a
    => FilePath
    -> IO (Either ParseException a)
decodeFileEither fp = either Left (either (Left . AesonException) Right) <$> decodeHelper (eventsFromFile fp)
