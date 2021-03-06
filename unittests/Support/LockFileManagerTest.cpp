//===- unittests/LockFileManagerTest.cpp - LockFileManager tests ----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "llvm/Support/LockFileManager.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "gtest/gtest.h"
#include <memory>

using namespace llvm;

namespace {

TEST(LockFileManagerTest, Basic) {
  SmallString<64> TmpDir;
  error_code EC;
  EC = sys::fs::createUniqueDirectory("LockFileManagerTestDir", TmpDir);
  ASSERT_FALSE(EC);

  SmallString<64> LockedFile(TmpDir);
  sys::path::append(LockedFile, "file.lock");

  {
    // The lock file should not exist, so we should successfully acquire it.
    LockFileManager Locked1(LockedFile);
    EXPECT_EQ(LockFileManager::LFS_Owned, Locked1.getState());

    // Attempting to reacquire the lock should fail.  Waiting on it would cause
    // deadlock, so don't try that.
    LockFileManager Locked2(LockedFile);
    EXPECT_NE(LockFileManager::LFS_Owned, Locked2.getState());
  }

  // Now that the lock is out of scope, the file should be gone.
  EXPECT_FALSE(sys::fs::exists(StringRef(LockedFile)));

  EC = sys::fs::remove(StringRef(TmpDir));
  ASSERT_FALSE(EC);
}

TEST(LockFileManagerTest, LinkLockExists) {
  SmallString<64> TmpDir;
  error_code EC;
  EC = sys::fs::createUniqueDirectory("LockFileManagerTestDir", TmpDir);
  ASSERT_FALSE(EC);

  SmallString<64> LockedFile(TmpDir);
  sys::path::append(LockedFile, "file");

  SmallString<64> FileLocK(TmpDir);
  sys::path::append(FileLocK, "file.lock");

  SmallString<64> TmpFileLock(TmpDir);
  sys::path::append(TmpFileLock, "file.lock-000");

  EC = sys::fs::create_link(TmpFileLock.str(), FileLocK.str());
#if defined(_WIN32)
  // Win32 cannot create link with nonexistent file, since create_link is
  // implemented as hard link.
  ASSERT_EQ(EC, errc::no_such_file_or_directory);
#else
  ASSERT_FALSE(EC);
#endif

  {
    // The lock file doesn't point to a real file, so we should successfully
    // acquire it.
    LockFileManager Locked(LockedFile);
    EXPECT_EQ(LockFileManager::LFS_Owned, Locked.getState());
  }

  // Now that the lock is out of scope, the file should be gone.
  EXPECT_FALSE(sys::fs::exists(StringRef(LockedFile)));

  EC = sys::fs::remove(StringRef(TmpDir));
  ASSERT_FALSE(EC);
}


TEST(LockFileManagerTest, RelativePath) {
  SmallString<64> TmpDir;
  error_code EC;
  EC = sys::fs::createUniqueDirectory("LockFileManagerTestDir", TmpDir);
  ASSERT_FALSE(EC);

  char PathBuf[1024];
  const char *OrigPath = getcwd(PathBuf, 1024);
  chdir(TmpDir.c_str());

  sys::fs::create_directory("inner");
  SmallString<64> LockedFile("inner");
  sys::path::append(LockedFile, "file");

  SmallString<64> FileLock(LockedFile);
  FileLock += ".lock";

  {
    // The lock file should not exist, so we should successfully acquire it.
    LockFileManager Locked(LockedFile);
    EXPECT_EQ(LockFileManager::LFS_Owned, Locked.getState());
    EXPECT_TRUE(sys::fs::exists(FileLock.str()));
  }

  // Now that the lock is out of scope, the file should be gone.
  EXPECT_FALSE(sys::fs::exists(LockedFile.str()));
  EXPECT_FALSE(sys::fs::exists(FileLock.str()));

  EC = sys::fs::remove("inner");
  ASSERT_FALSE(EC);
  EC = sys::fs::remove(StringRef(TmpDir));
#if defined(_WIN32)
  // Win32 cannot remove working directory.
  ASSERT_EQ(EC, errc::permission_denied);
#else
  ASSERT_FALSE(EC);
#endif

  chdir(OrigPath);

#if defined(_WIN32)
  EC = sys::fs::remove(StringRef(TmpDir));
  ASSERT_FALSE(EC);
#endif
}

} // end anonymous namespace
