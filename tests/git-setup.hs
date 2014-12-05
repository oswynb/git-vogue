{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- | Description: Test git repository setup.
module Main where

import           Control.Exception.Lifted
import           Control.Monad
import           Control.Monad.Base
import           Control.Monad.IO.Class      ()
import           Control.Monad.Trans.Control
import           Data.List
import           Data.Monoid
import           System.Directory
import           System.Exit
import           System.FilePath
import           System.Posix.Files
import           System.Posix.Temp
import           System.Process
import           Test.Hspec

import           Git.Vogue
import           Paths_git_vogue

main :: IO ()
main = hspec . describe "Git repository setup" $ do
    it "should install a new pre-commit hook" $
        withGitRepo $ \path -> do
            let hook = path </> ".git" </> "hooks" </> "pre-commit"

            -- Run the setup program.
            code <- runInRepo path
            code `shouldBe` ExitSuccess

            -- Check that it worked.
            checkPreCommitHook hook

    it "should skip an already correct pre-commit hook" $
        withGitRepo $ \path -> do
            let hook = path </> ".git" </> "hooks" </> "pre-commit"

            -- Create an existing hook to update.
            copyHookTemplateTo hook

            -- Run the setup program.
            code <- runInRepo path
            code `shouldBe` ExitSuccess

            -- Check that it worked.
            checkPreCommitHook hook

    it "should report a conflict pre-commit hook" $
        withGitRepo $ \path -> do
            let hook = path </> ".git" </> "hooks" </> "pre-commit"

            -- Create an existing hook to update.
            writeFile hook "echo YAY\n"
            setPermissions hook $ emptyPermissions
                { readable = True
                , executable = True
                }

            -- Run the setup program.
            code <- runInRepo path
            code `shouldBe` (ExitFailure 1)

-- | Execute the setup command in a git repository.
runInRepo
    :: FilePath
    -> IO ExitCode
runInRepo path = do
    pwd <- getCurrentDirectory
    let exe = pwd </> "dist/build/git-vogue/git-vogue"
    proc <- spawnCommand $
        "cd " <> path <> " && " <> exe <> " init"
    waitForProcess proc

-- | Check that a pre-commit hook script is "correct".
checkPreCommitHook
    :: FilePath
    -> IO ()
checkPreCommitHook hook = do
    -- Check the hook exists.
    exists <- fileExist hook
    unless exists $ error "Commit hook missing"

    -- Check the hook is executable.
    perm <- getPermissions hook
    unless (executable perm) $ error "Commit hook is not executable"

    -- Check it has our command in it.
    content <- readFile hook
    unless (preCommitCommand `isInfixOf` content) $
        error "Commit hook does not contain command"

-- | Create a git repository and run an action with it.
withGitRepo
    :: MonadBaseControl IO m
    => (FilePath -> m ())
    -> m ()
withGitRepo = bracket createRepo deleteRepo
  where
    createRepo = do
        path <- liftBase $ mkdtemp "/tmp/git-setup-test."
        liftBase $ callProcess "git" ["init", path]
        return path
    deleteRepo path =
        liftBase $ callProcess "rm" ["-rf", path]