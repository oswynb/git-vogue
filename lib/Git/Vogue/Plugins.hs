--
-- Copyright © 2013-2014 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Git.Vogue.Plugins where

import           Git.Vogue.Types

import           Control.Monad.IO.Class
import           Data.Monoid
import           Data.String
import           Data.String.Utils
import           Data.Text              (Text)
import qualified Data.Text              as T
import qualified Data.Text.IO           as T
import           System.Exit
import           System.Process

ioPluginExecutorImpl :: PluginExecutorImpl IO
ioPluginExecutorImpl =
    PluginExecutorImpl (f "fix") (f "check")
  where
    f arg (Plugin path) = do
        name <- getName path
        (status, stdout, stderr) <- readProcessWithExitCode path [arg] mempty
        let glommed = fromString $ stdout <> stderr
        return $ case status of
            ExitSuccess -> Success name glommed
            ExitFailure 1 -> Failure name glommed
            ExitFailure _ -> Catastrophe name glommed

    getName path = do
        (status, name, _) <- readProcessWithExitCode path ["name"] mempty
        return . PluginName . fromString . strip $ case status of
            ExitSuccess -> if null name then path else name
            ExitFailure _ -> path

colorize :: Status a -> Text
colorize (Success     (PluginName x) y) = "\x1b[32m" <> x <> " succeeded with " <> y <> "\x1b[0m"
colorize (Failure     (PluginName x) y) = "\x1b[33m" <> x <> " failed with "    <> y <> "\x1b[0m"
colorize (Catastrophe (PluginName x) y) = "\x1b[31m" <> x <> " exploded with "  <> y <> "\x1b[0m"

checkPlugins'
    :: MonadIO m
    => [Plugin]
    -> m ()
checkPlugins' ps = liftIO $ do
    st <- checkPlugins ioPluginExecutorImpl ps
    case st of
        Success{} ->
            exitSuccess
        Failure _ output -> do
            T.putStrLn output
            exitWith $ ExitFailure 1
        Catastrophe _ output -> do
            T.putStrLn output
            exitWith $ ExitFailure 2

fixPlugins'
    :: MonadIO m
    => [Plugin]
    -> m ()
fixPlugins' ps = liftIO $ do
    st <- fixPlugins ioPluginExecutorImpl ps
    case st of
        Success _ output -> do
            T.putStrLn output
            exitSuccess
        Failure _ output -> do
            T.putStrLn output
            exitWith $ ExitFailure 1
        Catastrophe _ output -> do
            T.putStrLn output
            exitWith $ ExitFailure 2

checkPlugins
    :: Monad m
    => PluginExecutorImpl m
    -> [Plugin]
    -> m (Status Check)
checkPlugins PluginExecutorImpl{..} ps = do
    rs <- mapM executeCheck ps
    return $ insertMax rs (T.unlines $ map colorize rs)

fixPlugins
    :: Monad m
    => PluginExecutorImpl m
    -> [Plugin]
    -> m (Status Fix)
fixPlugins PluginExecutorImpl{..} ps = do
    rs <- mapM executeFix ps
    return $ insertMax rs (T.unlines $ map colorize rs)

insertMax :: [Status a] -> Text -> Status a
insertMax rs txt =
    case maximum rs of
        Success{} -> Success mempty txt
        Failure{} -> Failure mempty txt
        Catastrophe{} -> Catastrophe mempty txt
