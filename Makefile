all : interpreter


interpreter : 
	ghc -o interpreter --make Main.hs 


clean :
	-rm -f *.hi *.o *.log *.aux *.dvi interpreter

