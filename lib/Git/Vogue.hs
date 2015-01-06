--
-- Copyright © 2013-2015 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE ScopedTypeVariables              #-}
{-# LANGUAGE TypeFamilies               #-}

module Git.Vogue where

import           Control.Monad.IO.Class
import Data.Traversable hiding (sequence)
import           Data.Text.Lazy         (Text)
import qualified Data.Text.Lazy         as T
import qualified Data.Text.Lazy.IO      as T
import           Formatting
import           System.Directory
import Data.Maybe
import Control.Applicative
import           System.Exit

import           Git.Vogue.Types

-- | Execute a git-vogue command.
runCommand
    :: forall m. (Applicative m, MonadIO m, Functor m)
    => VogueCommand
    -> SearchMode
    -> VCS m
    -> PluginDiscoverer m
    -> m ()
runCommand cmd search_mode VCS{..} PluginDiscoverer{..} = do
    findTopLevel >>= liftIO . setCurrentDirectory
    go cmd
  where
    go CmdInit = do
        already_there <- checkHook
        if already_there
            then success "Pre-commit hook is already installed"
            else do
                installHook
                installed <- checkHook
                if installed
                    then success "Successfully installed hook"
                    else failure "Hook failed to install"

    go CmdVerify = do
        installed <- checkHook
        if installed
            then success "Pre-commit hook currently installed"
            else failure "Pre-commit hook not installed"

    go CmdPlugins = do
        liftIO $  T.putStrLn "git-vogue knows about the following plugins:\n"
        discoverPlugins >>= liftIO . T.putStrLn . T.unlines . fmap pluginName

    go CmdRunCheck = do
        files <- getFiles search_mode
        plugins <- filter enabled <$> discoverPlugins
        for plugins (\p@Plugin{..} -> (p,) <$> runCheck files)
            >>= outputStatusAndExit

    go CmdRunFix = do
        files <- getFiles search_mode
        plugins <- filter enabled <$> discoverPlugins
        rs <- for plugins $ \p@Plugin{..} -> do
            r <- runCheck files
            case r of
                Failure{} -> do
                    r' <- runFix files
                    return $ Just (p, r')
                _  -> return Nothing

        outputStatusAndExit (catMaybes rs)

success, failure :: MonadIO m => Text -> m a
success msg = liftIO (T.putStrLn msg >> exitSuccess)
failure msg = liftIO (T.putStrLn msg >> exitFailure)

-- | Output the results of a run and exit with an appropriate return code
outputStatusAndExit
    :: MonadIO m
    => [(Plugin z, Result)]
    -> m ()
outputStatusAndExit rs = liftIO $
    case worst of
        Success output -> do
            T.putStrLn output
            exitSuccess
        Failure output -> do
            T.putStrLn output
            exitWith $ ExitFailure 1
        Catastrophe _ output -> do
            T.putStrLn output
            exitWith $ ExitFailure 2
  where
    worst =
        let txt = T.unlines $ fmap (uncurry colorize) rs
        in case maximum (fmap snd rs) of
            Success{} -> Success txt
            Failure{} -> Failure txt
            Catastrophe{} -> Catastrophe 0 txt

    colorize Plugin{..} (Success txt) =
        format ("\x1b[32m"
               % text
               % " succeeded\x1b[0m with:\n"
               % text) pluginName txt
    colorize Plugin{..} (Failure txt) =
        format ("\x1b[33m"
               % text
               % " failed\x1b[0m with:\n"
               % text) pluginName txt
    colorize Plugin{..} (Catastrophe txt ret) =
        format ("\x1b[31m"
            % text
            % " exploded \x1b[0m with exit code "
            % int
            %":\n"
            % text) pluginName txt ret
