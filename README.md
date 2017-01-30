# Installing prerequisites

On Ubuntu == 16.04:

```bash
# for haskell 8.0.2
echo "deb http://ppa.launchpad.net/hvr/ghc/ubuntu xenial main" | sudo tee -a /etc/apt/sources.list
echo "deb http://cz.archive.ubuntu.com/ubuntu xenial main" | sudo tee -a /etc/apt/sources.list
echo "deb http://security.ubuntu.com/ubuntu xenial-security main" | sudo tee -a /etc/apt/sources.list
sudo apt-get update
sudo apt-get install ghc-8.0.2 cabal-install-1.24 happy-1.19.5 zlib1g-dev 
export PATH=$PATH:/opt/ghc/8.0.2/bin:/opt/cabal/1.24/bin:/opt/happy/1.19.5/bin
```


```bash
cabal sandbox init
cabal sandbox add-source habs-runtime
cabal sandbox add-source habs-stdlib

cabal update
cabal install habs-runtime
cabal install habs-stdlib
cabal install mwc-random
cabal install clock
```

# Compiling the distributed-pa programs

```bash
# (optional) compiling ABS to Haskell, NEED TO install HABS compiler for that
#cabal exec habs -- src/*.abs -o src/gen/haskell
# manual modifications

cabal exec ghc -- --make -O src/gen/haskell/DisPATenDel.hs -main-is DisPATenDel 
cabal exec ghc -- --make -O src/gen/haskell/DisPATenDelO.hs -main-is DisPATenDelO 
```

# Running the distributed-pa programs on the cloud

TODO