c-----------------------------------------------------------------------
      subroutine riemann_aug_JCP_sp(maxiter,meqn,mwaves,hL,hR,huL,huR,
     &   hvL,hvR,bL,bR,uL,uR,vL,vR,delphi,sE1,sE2,drytol,g,sw,fw)

      ! solve shallow water equations given single left and right states
      ! This solver is described in J. Comput. Phys. (6): 3089-3113, March 2008
      ! Augmented Riemann Solvers for the Shallow Equations with Steady States and Inundation

      ! To use the original solver call with maxiter=1.

      ! This solver allows iteration when maxiter > 1. The iteration seems to help with
      ! instabilities that arise (with any solver) as flow becomes transcritical over variable topo
      ! due to loss of hyperbolicity.



      implicit none

      !input
      integer meqn,mwaves,maxiter
      real fw(meqn,mwaves)
      real sw(mwaves)
      real hL,hR,huL,huR,bL,bR,uL,uR,delphi,sE1,sE2
      real hvL,hvR,vL,vR
      real drytol,g


      !local
      integer m,mw,k,iter
      real A(3,3)
      real r(3,3)
      real lambda(3)
      real del(3)
      real beta(3)

      real delh,delhu,delb,delnorm
      real rare1st,rare2st,sdelta,raremin,raremax
      real criticaltol,convergencetol,raretol
      real s1s2bar,s1s2tilde,hbar,hLstar,hRstar,hustar
      real huRstar,huLstar,uRstar,uLstar,hstarHLL
      real deldelh,deldelphi
      real s1m,s2m,hm
      real det1,det2,det3,determinant

      logical rare1,rare2,rarecorrector,rarecorrectortest,sonic


      !determine del vectors
      delh = hR-hL
      delhu = huR-huL
      delb = bR-bL
      delnorm = delh**2 + delphi**2

      call riemanntype_sp(hL,hR,uL,uR,hm,s1m,s2m,rare1,rare2,
     &                                          1,drytol,g)

      lambda(1)= min(sE1,s2m) !Modified Einfeldt speed
      lambda(3)= max(sE2,s1m) !Modified Eindfeldt speed
      sE1=lambda(1)
      sE2=lambda(3)
      hstarHLL = max((huL-huR+sE2*hR-sE1*hL)/(sE2-sE1),0.e0) ! middle state in an HLL solve

c     !determine the middle entropy corrector wave------------------------
      rarecorrectortest=.false.
      rarecorrector=.false.
      if (rarecorrectortest) then
         sdelta=lambda(3)-lambda(1)
         raremin = 0.5e0
         raremax = 0.9e0
         if (rare1.and.sE1*s1m.lt.0.e0) raremin=0.2e0
         if (rare2.and.sE2*s2m.lt.0.e0) raremin=0.2e0
         if (rare1.or.rare2) then
            !see which rarefaction is larger
            rare1st=3.e0*(sqrt(g*hL)-sqrt(g*hm))
            rare2st=3.e0*(sqrt(g*hR)-sqrt(g*hm))
            if (max(rare1st,rare2st).gt.raremin*sdelta.and.
     &         max(rare1st,rare2st).lt.raremax*sdelta) then
                  rarecorrector=.true.
               if (rare1st.gt.rare2st) then
                  lambda(2)=s1m
               elseif (rare2st.gt.rare1st) then
                  lambda(2)=s2m
               else
                  lambda(2)=0.5e0*(s1m+s2m)
               endif
            endif
         endif
         if (hstarHLL.lt.min(hL,hR)/5.e0) rarecorrector=.false.
      endif

      if (abs(lambda(2)) .lt. 1.e-20) lambda(2) = 0.e0
      do mw=1,mwaves
         r(1,mw)=1.e0
         r(2,mw)=lambda(mw)
         r(3,mw)=(lambda(mw))**2
      enddo
      if (.not.rarecorrector) then
         lambda(2) = 0.5e0*(lambda(1)+lambda(3))
c         lambda(2) = max(min(0.5e0*(s1m+s2m),sE2),sE1)
         if (abs(lambda(2)) .lt. 1.e-20) lambda(2) = 0.e0
         r(1,2)=0.e0
         r(2,2)=0.e0
         r(3,2)=1.e0
      endif
c     !---------------------------------------------------

c     !determine the steady state wave -------------------
      criticaltol = 1.e-6
      deldelh = -delb
      deldelphi = -g*0.5e0*(hR+hL)*delb

c     !determine a few quanitites needed for steady state wave if iterated
      hLstar=hL
      hRstar=hR
      uLstar=uL
      uRstar=uR
      huLstar=uLstar*hLstar
      huRstar=uRstar*hRstar

      !iterate to better determine the steady state wave
      convergencetol=1.e-6
      do iter=1,maxiter
         !determine steady state wave (this will be subtracted from the delta vectors)
         if (min(hLstar,hRstar).lt.drytol.and.rarecorrector) then
            rarecorrector=.false.
            hLstar=hL
            hRstar=hR
            uLstar=uL
            uRstar=uR
            huLstar=uLstar*hLstar
            huRstar=uRstar*hRstar
            lambda(2) = 0.5e0*(lambda(1)+lambda(3))
c           lambda(2) = max(min(0.5e0*(s1m+s2m),sE2),sE1)
            if (abs(lambda(2)) .lt. 1.e-20) lambda(2) = 0.e0
            r(1,2)=0.e0
            r(2,2)=0.e0
            r(3,2)=1.e0
         endif

         hbar =  max(0.5e0*(hLstar+hRstar),0.e0)
         s1s2bar = 0.25e0*(uLstar+uRstar)**2 - g*hbar
         s1s2tilde= max(0.e0,uLstar*uRstar) - g*hbar

c        !find if sonic problem
         sonic=.false.
         if (abs(s1s2bar).le.criticaltol) sonic=.true.
         if (s1s2bar*s1s2tilde.le.criticaltol) sonic=.true.
         if (s1s2bar*sE1*sE2.le.criticaltol) sonic = .true.
         if (min(abs(sE1),abs(sE2)).lt.criticaltol) sonic=.true.
         if (sE1.lt.0.e0.and.s1m.gt.0.e0) sonic = .true.
         if (sE2.gt.0.e0.and.s2m.lt.0.e0) sonic = .true.
         if ((uL+sqrt(g*hL))*(uR+sqrt(g*hR)).lt.0.e0) sonic=.true.
         if ((uL-sqrt(g*hL))*(uR-sqrt(g*hR)).lt.0.e0) sonic=.true.

c        !find jump in h, deldelh
         if (sonic) then
            deldelh =  -delb
         else
            deldelh = delb*g*hbar/s1s2bar
         endif
c        !find bounds in case of critical state resonance, or negative states
         if (sE1.lt.-criticaltol.and.sE2.gt.criticaltol) then
            deldelh = min(deldelh,hstarHLL*(sE2-sE1)/sE2)
            deldelh = max(deldelh,hstarHLL*(sE2-sE1)/sE1)
         elseif (sE1.ge.criticaltol) then
            deldelh = min(deldelh,hstarHLL*(sE2-sE1)/sE1)
            deldelh = max(deldelh,-hL)
         elseif (sE2.le.-criticaltol) then
            deldelh = min(deldelh,hR)
            deldelh = max(deldelh,hstarHLL*(sE2-sE1)/sE2)
         endif

c        !find jump in phi, deldelphi
         if (sonic) then
            deldelphi = -g*hbar*delb
         else
            deldelphi = -delb*g*hbar*s1s2tilde/s1s2bar
         endif
c        !find bounds in case of critical state resonance, or negative states
         deldelphi=min(deldelphi,g*max(-hLstar*delb,-hRstar*delb))
         deldelphi=max(deldelphi,g*min(-hLstar*delb,-hRstar*delb))

         del(1)=delh-deldelh
         del(2)=delhu
         del(3)=delphi-deldelphi

c        !Determine determinant of eigenvector matrix========
         det1=r(1,1)*(r(2,2)*r(3,3)-r(2,3)*r(3,2))
         det2=r(1,2)*(r(2,1)*r(3,3)-r(2,3)*r(3,1))
         det3=r(1,3)*(r(2,1)*r(3,2)-r(2,2)*r(3,1))
         determinant=det1-det2+det3

c        !solve for beta(k) using Cramers Rule=================
         do k=1,3
            do mw=1,3
               do m=1,3
                  A(m,mw)=r(m,mw)
                  A(m,k)=del(m)
               enddo
            enddo
            det1=A(1,1)*(A(2,2)*A(3,3)-A(2,3)*A(3,2))
            det2=A(1,2)*(A(2,1)*A(3,3)-A(2,3)*A(3,1))
            det3=A(1,3)*(A(2,1)*A(3,2)-A(2,2)*A(3,1))
            beta(k)=(det1-det2+det3)/determinant
         enddo

         !exit if things aren't changing
         if (abs(del(1)**2+del(3)**2-delnorm).lt.convergencetol) exit
         delnorm = del(1)**2+del(3)**2
         !find new states qLstar and qRstar on either side of interface
         hLstar=hL
         hRstar=hR
         uLstar=uL
         uRstar=uR
         huLstar=uLstar*hLstar
         huRstar=uRstar*hRstar
         do mw=1,mwaves
            if (lambda(mw).lt.0.e0) then
               hLstar= hLstar + beta(mw)*r(1,mw)
               huLstar= huLstar + beta(mw)*r(2,mw)
            endif
         enddo
         do mw=mwaves,1,-1
            if (lambda(mw).gt.0.e0) then
               hRstar= hRstar - beta(mw)*r(1,mw)
               huRstar= huRstar - beta(mw)*r(2,mw)
            endif
         enddo

         if (hLstar.gt.drytol) then
            uLstar=huLstar/hLstar
         else
            hLstar=max(hLstar,0.e0)
            uLstar=0.e0
         endif
         if (hRstar.gt.drytol) then
            uRstar=huRstar/hRstar
         else
            hRstar=max(hRstar,0.e0)
            uRstar=0.e0
         endif

      enddo ! end iteration on Riemann problem

      do mw=1,mwaves
         sw(mw)=lambda(mw)
         fw(1,mw)=beta(mw)*r(2,mw)
         fw(2,mw)=beta(mw)*r(3,mw)
         fw(3,mw)=beta(mw)*r(2,mw)
      enddo
      !find transverse components (ie huv jumps).
      fw(3,1)=fw(3,1)*vL
      fw(3,3)=fw(3,3)*vR
      fw(3,2)= hR*uR*vR - hL*uL*vL - fw(3,1)- fw(3,3)

      return

      end !subroutine riemann_aug_JCP-------------------------------------------------


c-----------------------------------------------------------------------
      subroutine riemann_ssqfwave_sp(maxiter,meqn,mwaves,hL,hR,huL,huR,
     &    hvL,hvR,bL,bR,uL,uR,vL,vR,delphi,sE1,sE2,drytol,g,sw,fw)

      ! solve shallow water equations given single left and right states
      ! steady state wave is subtracted from delta [q,f]^T before decomposition

      implicit none

      !input
      integer meqn,mwaves,maxiter

      real hL,hR,huL,huR,bL,bR,uL,uR,delphi,sE1,sE2
      real vL,vR,hvL,hvR
      real drytol,g

      !local
      integer iter

      logical sonic

      real delh,delhu,delb,delhdecomp,delphidecomp
      real s1s2bar,s1s2tilde,hbar,hLstar,hRstar,hustar
      real uRstar,uLstar,hstarHLL
      real deldelh,deldelphi
      real alpha1,alpha2,beta1,beta2,delalpha1,delalpha2
      real criticaltol,convergencetol
      real sL,sR
      real uhat,chat,sRoe1,sRoe2

      real sw(mwaves)
      real fw(meqn,mwaves)

      !determine del vectors
      delh = hR-hL
      delhu = huR-huL
      delb = bR-bL

      convergencetol= 1.e-16
      criticaltol = tiny(1.0)

      deldelh = -delb
      deldelphi = -g*0.5e0*(hR+hL)*delb


!     !if no source term, skip determining steady state wave
      if (abs(delb).gt.0.e0) then
!
         !determine a few quanitites needed for steady state wave if iterated
         hLstar=hL
         hRstar=hR
         uLstar=uL
         uRstar=uR
         hstarHLL = max((huL-huR+sE2*hR-sE1*hL)/(sE2-sE1),0.e0) ! middle state in an HLL solve

         alpha1=0.e0
         alpha2=0.e0

!        !iterate to better determine Riemann problem
         do iter=1,maxiter

            !determine steady state wave (this will be subtracted from the delta vectors)
            hbar =  max(0.5e0*(hLstar+hRstar),0.e0)
            s1s2bar = 0.25e0*(uLstar+uRstar)**2 - g*hbar
            s1s2tilde= max(0.e0,uLstar*uRstar) - g*hbar


c           !find if sonic problem
            sonic=.false.
            if (abs(s1s2bar).le.criticaltol) sonic=.true.
            if (s1s2bar*s1s2tilde.le.criticaltol) sonic=.true.
            if (s1s2bar*sE1*sE2.le.criticaltol) sonic = .true.
            if (min(abs(sE1),abs(sE2)).lt.criticaltol) sonic=.true.

c           !find jump in h, deldelh
            if (sonic) then
               deldelh =  -delb
            else
               deldelh = delb*g*hbar/s1s2bar
            endif
!           !bounds in case of critical state resonance, or negative states
            if (sE1.lt.-criticaltol.and.sE2.gt.criticaltol) then
               deldelh = min(deldelh,hstarHLL*(sE2-sE1)/sE2)
               deldelh = max(deldelh,hstarHLL*(sE2-sE1)/sE1)
            elseif (sE1.ge.criticaltol) then
               deldelh = min(deldelh,hstarHLL*(sE2-sE1)/sE1)
               deldelh = max(deldelh,-hL)
            elseif (sE2.le.-criticaltol) then
               deldelh = min(deldelh,hR)
               deldelh = max(deldelh,hstarHLL*(sE2-sE1)/sE2)
            endif

c           !find jump in phi, deldelphi
            if (sonic) then
               deldelphi = -g*hbar*delb
            else
               deldelphi = -delb*g*hbar*s1s2tilde/s1s2bar
            endif
!           !bounds in case of critical state resonance, or negative states
            deldelphi=min(deldelphi,g*max(-hLstar*delb,-hRstar*delb))
            deldelphi=max(deldelphi,g*min(-hLstar*delb,-hRstar*delb))

!---------determine fwaves ------------------------------------------

!           !first decomposition
            delhdecomp = delh-deldelh
            delalpha1 = (sE2*delhdecomp - delhu)/(sE2-sE1)-alpha1
            alpha1 = alpha1 + delalpha1
            delalpha2 = (delhu - sE1*delhdecomp)/(sE2-sE1)-alpha2
            alpha2 = alpha2 + delalpha2

            !second decomposition
            delphidecomp = delphi - deldelphi
            beta1 = (sE2*delhu - delphidecomp)/(sE2-sE1)
            beta2 = (delphidecomp - sE1*delhu)/(sE2-sE1)

            if ((delalpha2**2+delalpha1**2).lt.convergencetol**2) then
               exit
            endif
!
            if (sE2.gt.0.e0.and.sE1.lt.0.e0) then
               hLstar=hL+alpha1
               hRstar=hR-alpha2
c               hustar=huL+alpha1*sE1
               hustar = huL + beta1
            elseif (sE1.ge.0.e0) then
               hLstar=hL
               hustar=huL
               hRstar=hR - alpha1 - alpha2
            elseif (sE2.le.0.e0) then
               hRstar=hR
               hustar=huR
               hLstar=hL + alpha1 + alpha2
            endif
!
            if (hLstar.gt.drytol) then
               uLstar=hustar/hLstar
            else
               hLstar=max(hLstar,0.e0)
               uLstar=0.e0
            endif
!
            if (hRstar.gt.drytol) then
               uRstar=hustar/hRstar
            else
               hRstar=max(hRstar,0.e0)
               uRstar=0.e0
            endif

         enddo
      endif

      delhdecomp = delh - deldelh
      delphidecomp = delphi - deldelphi

      !first decomposition
      alpha1 = (sE2*delhdecomp - delhu)/(sE2-sE1)
      alpha2 = (delhu - sE1*delhdecomp)/(sE2-sE1)

      !second decomposition
      beta1 = (sE2*delhu - delphidecomp)/(sE2-sE1)
      beta2 = (delphidecomp - sE1*delhu)/(sE2-sE1)

      ! 1st nonlinear wave
      fw(1,1) = alpha1*sE1
      fw(2,1) = beta1*sE1
      fw(3,1) = fw(1,1)*vL
      ! 2nd nonlinear wave
      fw(1,3) = alpha2*sE2
      fw(2,3) = beta2*sE2
      fw(3,3) = fw(1,3)*vR
      ! advection of transverse wave
      fw(1,2) = 0.e0
      fw(2,2) = 0.e0
      fw(3,2) = hR*uR*vR - hL*uL*vL -fw(3,1)-fw(3,3)
      !speeds
      sw(1)=sE1
      sw(2)=0.5e0*(sE1+sE2)
      sw(3)=sE2

      return

      end subroutine !-------------------------------------------------


c-----------------------------------------------------------------------
      subroutine riemann_fwave_sp(meqn,mwaves,hL,hR,huL,huR,hvL,hvR,
     &            bL,bR,uL,uR,vL,vR,delphi,s1,s2,drytol,g,sw,fw)
      ! solve shallow water equations given single left and right states
      ! solution has two waves.
      ! flux - source is decomposed.

      implicit none

      !input
      integer meqn,mwaves

      real hL,hR,huL,huR,bL,bR,uL,uR,delphi,s1,s2
      real hvL,hvR,vL,vR
      real drytol,g

      real sw(mwaves)
      real fw(meqn,mwaves)

      !local
      real delh,delhu,delb,delhdecomp,delphidecomp
      real deldelh,deldelphi
      real beta1,beta2


      !determine del vectors
      delh = hR-hL
      delhu = huR-huL
      delb = bR-bL

      deldelphi = -g*0.5e0*(hR+hL)*delb
      delphidecomp = delphi - deldelphi

      !flux decomposition
      beta1 = (s2*delhu - delphidecomp)/(s2-s1)
      beta2 = (delphidecomp - s1*delhu)/(s2-s1)

      sw(1)=s1
      sw(2)=0.5e0*(s1+s2)
      sw(3)=s2
      ! 1st nonlinear wave
      fw(1,1) = beta1
      fw(2,1) = beta1*s1
      fw(3,1) = beta1*vL
      ! 2nd nonlinear wave
      fw(1,3) = beta2
      fw(2,3) = beta2*s2
      fw(3,3) = beta2*vR
      ! advection of transverse wave
      fw(1,2) = 0.e0
      fw(2,2) = 0.e0
      fw(3,2) = huR*vR - huL*vL-fw(3,1)-fw(3,3)
      return

      end !subroutine -------------------------------------------------





c=============================================================================
      subroutine riemanntype_sp(hL,hR,uL,uR,hm,s1m,s2m,rare1,rare2,
     &             maxiter,drytol,g)

      !determine the Riemann structure (wave-type in each family)


      implicit none

      !input
      real hL,hR,uL,uR,drytol,g
      integer maxiter

      !output
      real s1m,s2m
      logical rare1,rare2

      !local
      real hm,u1m,u2m,um,delu
      real h_max,h_min,h0,F_max,F_min,dfdh,F0,slope,gL,gR
      integer iter



c     !Test for Riemann structure

      h_min=min(hR,hL)
      h_max=max(hR,hL)
      delu=uR-uL

      if (h_min.le.drytol) then
         hm=0.e0
         um=0.e0
         s1m=uR+uL-2.e0*sqrt(g*hR)+2.e0*sqrt(g*hL)
         s2m=uR+uL-2.e0*sqrt(g*hR)+2.e0*sqrt(g*hL)
         if (hL.le.0.e0) then
            rare2=.true.
            rare1=.false.
         else
            rare1=.true.
            rare2=.false.
         endif

      else
         F_min= delu+2.e0*(sqrt(g*h_min)-sqrt(g*h_max))
         F_max= delu +
     &         (h_max-h_min)*(sqrt(.5e0*g*(h_max+h_min)/(h_max*h_min)))

         if (F_min.gt.0.e0) then !2-rarefactions

            hm=(1.e0/(16.e0*g))*
     &               max(0.e0,-delu+2.e0*(sqrt(g*hL)+sqrt(g*hR)))**2
            um=sign(1.e0,hm)*(uL+2.e0*(sqrt(g*hL)-sqrt(g*hm)))

            s1m=uL+2.e0*sqrt(g*hL)-3.e0*sqrt(g*hm)
            s2m=uR-2.e0*sqrt(g*hR)+3.e0*sqrt(g*hm)

            rare1=.true.
            rare2=.true.

         elseif (F_max.le.0.e0) then !2 shocks

c           !root finding using a Newton iteration on sqrt(h)===
            h0=h_max
            do iter=1,maxiter
               gL=sqrt(.5e0*g*(1/h0 + 1/hL))
               gR=sqrt(.5e0*g*(1/h0 + 1/hR))
               F0=delu+(h0-hL)*gL + (h0-hR)*gR
               dfdh=gL-g*(h0-hL)/(4.e0*(h0**2)*gL)+
     &                   gR-g*(h0-hR)/(4.e0*(h0**2)*gR)
               slope=2.e0*sqrt(h0)*dfdh
               h0=(sqrt(h0)-F0/slope)**2
            enddo
               hm=h0
               u1m=uL-(hm-hL)*sqrt((.5e0*g)*(1/hm + 1/hL))
               u2m=uR+(hm-hR)*sqrt((.5e0*g)*(1/hm + 1/hR))
               um=.5e0*(u1m+u2m)

               s1m=u1m-sqrt(g*hm)
               s2m=u2m+sqrt(g*hm)
               rare1=.false.
               rare2=.false.

         else !one shock one rarefaction
            h0=h_min

            do iter=1,maxiter
               F0=delu + 2.e0*(sqrt(g*h0)-sqrt(g*h_max))
     &                  + (h0-h_min)*sqrt(.5e0*g*(1/h0+1/h_min))
               slope=(F_max-F0)/(h_max-h_min)
               h0=h0-F0/slope
            enddo

            hm=h0
            if (hL.gt.hR) then
               um=uL+2.e0*sqrt(g*hL)-2.e0*sqrt(g*hm)
               s1m=uL+2.e0*sqrt(g*hL)-3.e0*sqrt(g*hm)
               s2m=uL+2.e0*sqrt(g*hL)-sqrt(g*hm)
               rare1=.true.
               rare2=.false.
            else
               s2m=uR-2.e0*sqrt(g*hR)+3.e0*sqrt(g*hm)
               s1m=uR-2.e0*sqrt(g*hR)+sqrt(g*hm)
               um=uR-2.e0*sqrt(g*hR)+2.e0*sqrt(g*hm)
               rare2=.true.
               rare1=.false.
            endif
         endif
      endif

      return

      end ! subroutine riemanntype----------------------------------------------------------------
