import {Injectable} from '@angular/core';

@Injectable({providedIn:'root'})
export class Api {
  // Corrigé : un chemin relatif ('/api/v1') supposait que ce front
  // serait servi depuis la même origine que le backend -- vrai en dev
  // local (proxy Angular), faux une fois déployé comme site statique
  // séparé. Confirmé via la documentation officielle Render avant de
  // corriger : "The static site is a passive bundle of files. It never
  // proxies traffic." -- un site statique ne peut PAS rediriger /api/*
  // vers un serveur externe via une règle de réécriture (la destination
  // doit être un chemin interne, jamais une URL complète). D'où
  // l'échec silencieux de la tentative précédente (render.yaml avec une
  // règle de réécriture vers une URL absolue, rejetée par Render même
  // si le site lui-même s'est déployé avec succès).
  // URL absolue en dur plutôt qu'un fichier d'environnement Angular :
  // un seul backend réel existe pour ce projet, l'ajout d'un système de
  // configuration multi-environnement serait une complexité sans
  // bénéfice réel ici.
  base='https://veyra-wr6p.onrender.com/api/v1';
  private refreshPromise:Promise<boolean>|null=null;

  async request(path:string,init:RequestInit={},retried=false):Promise<any>{
    const token=localStorage.getItem('accessToken');
    const headers=new Headers(init.headers);
    if(init.body)headers.set('Content-Type','application/json');
    if(token)headers.set('Authorization','Bearer '+token);
    const response=await fetch(this.base+path,{...init,headers});

    if(response.status===401&&!retried&&!path.startsWith('/auth/')){
      const refreshed=await this.refreshAccessToken();
      if(refreshed)return this.request(path,init,true);
    }

    if(!response.ok){
      let error:any={code:'HTTP_'+response.status};
      try{error=await response.json();}catch{}
      throw error;
    }
    return response.status===204?null:response.json();
  }

  // request() always parses JSON -- documents/{id}/content returns raw
  // bytes (image/PDF), which would throw trying to JSON-parse it.
  // Separate method rather than a flag on request(), to keep the much
  // more common JSON path simple and not risk it accidentally taking
  // the blob branch.
  async requestBlob(path:string,retried=false):Promise<Blob>{
    const token=localStorage.getItem('accessToken');
    const headers=new Headers();
    if(token)headers.set('Authorization','Bearer '+token);
    const response=await fetch(this.base+path,{headers});
    // Bug réel trouvé en comparant avec request() ci-dessus : cette
    // méthode n'a jamais eu la même logique de retry sur 401. Un admin
    // dont le token venait tout juste d'expirer en consultant un
    // document KYC recevait "Document introuvable ou accès refusé"
    // (message trompeur -- le document existe, c'est juste le token qui
    // est expiré) plutôt que le rafraîchissement silencieux normal.
    if(response.status===401&&!retried){
      const refreshed=await this.refreshAccessToken();
      if(refreshed)return this.requestBlob(path,true);
    }
    if(!response.ok)throw new Error('HTTP_'+response.status);
    return response.blob();
  }

  private async refreshAccessToken():Promise<boolean>{
    if(this.refreshPromise)return this.refreshPromise;
    this.refreshPromise=(async()=>{
      const refreshToken=localStorage.getItem('refreshToken');
      if(!refreshToken)return false;
      try{
        const response=await fetch(this.base+'/auth/refresh',{
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body:JSON.stringify({refreshToken,deviceName:'web'})
        });
        if(!response.ok)throw new Error('refresh failed');
        const result=await response.json();
        localStorage.setItem('accessToken',result.accessToken);
        localStorage.setItem('refreshToken',result.refreshToken);
        return true;
      }catch{
        this.logout();
        return false;
      }finally{
        this.refreshPromise=null;
      }
    })();
    return this.refreshPromise;
  }

  async login(email:string,password:string){
    const result=await this.request('/auth/login',{
      method:'POST',
      body:JSON.stringify({email,password,deviceName:'web'})
    });
    localStorage.setItem('accessToken',result.accessToken);
    localStorage.setItem('refreshToken',result.refreshToken);
    return result;
  }

  me(){return this.request('/me');}

  logout(){
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    // Bug réel trouvé en lisant views/partner.ts : partnerId est lu
    // depuis localStorage au démarrage du composant (`localStorage.
    // getItem('partnerId')`) et n'était jamais nettoyé ici. Le backend
    // reste protégé (chaque endpoint /partner/{id}/... vérifie
    // l'appartenance réelle via member(), donc pas de fuite de données
    // -- juste un 403 silencieux avalé en "Aucune réservation"), mais
    // sur un poste partagé (réception d'un hôtel/restaurant), la
    // personne suivante qui se connecte avec son propre compte hérite
    // de l'ID du partenaire précédent et voit un encart "Partenaire
    // actif" trompeur tant qu'elle ne clique pas sur "Changer" sans
    // comprendre pourquoi. Nettoyé ici, au même endroit que les tokens,
    // pour couvrir aussi bien le clic "Déconnexion" que la
    // déconnexion automatique déclenchée par un refresh échoué.
    localStorage.removeItem('partnerId');
  }

  adminDashboard(){return this.request('/admin/dashboard');}
  adminBookings(){return this.request('/admin/bookings');}
  adminDrivers(){return this.request('/admin/drivers');}
  adminDriverDocuments(id:string){return this.request('/admin/drivers/'+id+'/documents');}
  adminPartners(){return this.request('/admin/partners');}
  approveDriver(id:string){return this.request('/admin/drivers/'+id+'/approve',{method:'POST'});}
  rejectDriver(id:string,reasonCode:string){return this.request('/admin/drivers/'+id+'/reject',{method:'POST',body:JSON.stringify({reasonCode})});}
  approvePartner(id:string){return this.request('/admin/partners/'+id+'/approve',{method:'POST'});}
  suspendPartner(id:string){return this.request('/admin/partners/'+id+'/suspend',{method:'POST'});}
  setStandardCommission(bps:number){return this.request('/admin/config/commission/standard',{method:'POST',body:JSON.stringify({bps})});}
  setPartnerCommission(id:string,bps:number){return this.request('/admin/config/commission/partner/'+id,{method:'POST',body:JSON.stringify({bps})});}
  getCancellationPolicy(){return this.request('/admin/config/cancellation-policy');}
  setCancellationPolicy(body:any){return this.request('/admin/config/cancellation-policy',{method:'POST',body:JSON.stringify(body)});}
  getOfferVisibility(){return this.request('/admin/config/offer-visibility');}
  setOfferVisibility(mode:string){return this.request('/admin/config/offer-visibility',{method:'POST',body:JSON.stringify({mode})});}
  setPartnerCredit(id:string,creditLimitMinor:number,paymentTermsDays:number,billingCycle:string){return this.request('/admin/partners/'+id+'/credit',{method:'PUT',body:JSON.stringify({creditLimitMinor,paymentTermsDays,billingCycle})});}
  cashDebts(){return this.request('/finance/cash-debts');}
  customerDebts(){return this.request('/finance/customer-debts');}
  payables(){return this.request('/finance/payables');}
  settleDebt(id:string,amountMinor:number){return this.request('/finance/cash-debts/'+id+'/settle?amountMinor='+amountMinor,{method:'POST'});}
  settleCustomerDebt(id:string,amountMinor:number){return this.request('/finance/customer-debts/'+id+'/settle?amountMinor='+amountMinor,{method:'POST'});}
  markPayablePaid(id:string){return this.request('/finance/payables/'+id+'/mark-paid',{method:'POST'});}
  generatePartnerInvoice(partnerId:string,from:string,to:string){return this.request('/finance/partners/'+partnerId+'/invoices/generate?from='+encodeURIComponent(from)+'&to='+encodeURIComponent(to),{method:'POST'});}
  supportTimeline(id:string){return this.request('/support/bookings/'+id+'/timeline');}
  createPartner(body:any){return this.request('/partner/organizations',{method:'POST',body:JSON.stringify(body)});}
  partnerOrganizations(){return this.request('/partner/organizations');}
  partnerFinance(id:string){return this.request('/partner/'+id+'/finance');}
  partnerBookings(id:string){return this.request('/partner/'+id+'/bookings');}
  partnerBeneficiaries(id:string){return this.request('/partner/'+id+'/beneficiaries');}
  createPartnerBeneficiary(id:string,body:any){return this.request('/partner/'+id+'/beneficiaries',{method:'POST',body:JSON.stringify(body)});}
  partnerInvoices(id:string){return this.request('/partner/'+id+'/invoices');}
  autocomplete(q:string){return this.request('/addresses/autocomplete?q='+encodeURIComponent(q));}
  vehicleCategories(){return this.request('/reference/vehicle-categories');}
  createScheduledBooking(body:any){return this.request('/scheduled-bookings',{method:'POST',body:JSON.stringify(body)});}
  myBookings(){return this.request('/scheduled-bookings');}
  bookingDetail(id:string){return this.request('/scheduled-bookings/'+id);}
  bookingTimeline(id:string){return this.request('/scheduled-bookings/'+id+'/timeline');}
  cancelBooking(id:string){return this.request('/bookings/'+id+'/cancel',{method:'POST'});}
  bookingLocation(id:string){return this.request('/bookings/'+id+'/location');}
  bookingOffers(id:string){return this.request('/scheduled-bookings/'+id+'/offers');}
  acceptOffer(bookingId:string,offerId:string){return this.request('/scheduled-bookings/'+bookingId+'/offers/'+offerId+'/accept',{method:'POST'});}
}
