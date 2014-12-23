-- | Description: Check with "cabal check".
module Main where

import           Control.Applicative
import           Control.Monad
import           Data.Monoid
import           Language.Haskell.HLint3
import           Options.Applicative
import           System.Directory
import           System.Exit
import           System.FilePath
import           Utilities.HaskellFiles

data Command
    -- | Check the project for problems.
    = CmdCheck
    -- | Fix problems in the project.
    | CmdFix
    -- | Report details.
    | CmdName

execute
    :: Command
    -> IO ()
execute cmd = case cmd of
    CmdName  -> putStrLn "hlint"
    CmdCheck -> hlintDirs ["./"]
    CmdFix   -> exitFailure

optionsParser :: Parser Command
optionsParser = subparser
    (  command "name" (info pName mempty)
    <> command "check" (info pCheck mempty)
    <> command "fix" (info pFix mempty)
    )
  where
    pName = pure CmdName
    pCheck = pure CmdCheck
    pFix = pure CmdFix

main :: IO ()
main = execParser opts >>= execute
  where
    opts = info (helper <*> optionsParser)
        ( fullDesc
        <> progDesc "Check your Haskell project for hlint-related problems."
        <> header "git-vogue-hlint - check for hlint problems" )

-- | Run hlint on a list of directories.
hlintDirs :: [FilePath] -> IO ()
hlintDirs dirs = do
    s <- autoSettings
    files <- mapM getSourceFilesForDir dirs
    ig <- mapM (hlintFile s) $ concat files
    let ideas = concat ig
    unless (null ideas) $
        do  print ideas
            exitFailure

-- | Run hlint on a single file.
hlintFile :: (ParseFlags, [Classify], Hint) -> FilePath -> IO [Idea]
hlintFile (flags, classify, hint) f = do
    Right m <- parseModuleEx flags f Nothing
    return $ applyHints classify hint [m]
