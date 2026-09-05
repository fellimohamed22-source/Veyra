import {Injectable} from '@angular/core';

@Injectable({providedIn:'root'})
export class Api {
  base='/api/v1';

  async request(path:string,init:RequestInit={}){
    const token=localStorage.getItem('accessToken');
    const headers=new Headers(init.headers);
    if(init.body)headers.set('Content-Type','application/json');
    if(token)headers.set('Authorization','Bearer '+token);
    const response=await fetch(this.base+path,{...init,headers});
    if(!response.ok){
      let error:any={code:'HTTP_'+response.status};
      try{error=await response.json();}catch{}
      throw error;
    }
    return response.status===204?null:response.json();
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

  logout(){
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
  }

  adminDashboard(){return this.request('/admin/dashboard');}
  adminBookings(){return this.request('/admin/bookings');}
  adminDrivers(){return this.request('/admin/drivers');}
  adminPartners(){return this.request('/admin/partners');}
  approveDriver(id:string){return this.request('/admin/drivers/'+id+'/approve',{method:'POST'});}
  rejectDriver(id:string,reasonCode:string){return this.request('/admin/drivers/'+id+'/reject',{method:'POST',body:JSON.stringify({reasonCode})});}
  approvePartner(id:string){return this.request('/admin/partners/'+id+'/approve',{method:'POST'});}
  suspendPartner(id:string){return this.request('/admin/partners/'+id+'/suspend',{method:'POST'});}
  setStandardCommission(bps:number){return this.request('/admin/config/commission/standard',{method:'POST',body:JSON.stringify({bps})});}
  setPartnerCommission(id:string,bps:number){return this.request('/admin/config/commission/partner/'+id,{method:'POST',body:JSON.stringify({bps})});}
  setPartnerCredit(id:string,creditLimitMinor:number,paymentTermsDays:number,billingCycle:string){return this.request('/admin/partners/'+id+'/credit',{method:'PUT',body:JSON.stringify({creditLimitMinor,paymentTermsDays,billingCycle})});}
  cashDebts(){return this.request('/finance/cash-debts');}
  payables(){return this.request('/finance/payables');}
  settleDebt(id:string,amountMinor:number){return this.request('/finance/cash-debts/'+id+'/settle?amountMinor='+amountMinor,{method:'POST'});}
  generatePartnerInvoice(partnerId:string,from:string,to:string){return this.request('/finance/partners/'+partnerId+'/invoices/generate?from='+encodeURIComponent(from)+'&to='+encodeURIComponent(to),{method:'POST'});}
  supportTimeline(id:string){return this.request('/support/bookings/'+id+'/timeline');}
  createPartner(body:any){return this.request('/partner/organizations',{method:'POST',body:JSON.stringify(body)});}
  partnerFinance(id:string){return this.request('/partner/'+id+'/finance');}
  autocomplete(q:string){return this.request('/addresses/autocomplete?q='+encodeURIComponent(q));}
  vehicleCategories(){return this.request('/reference/vehicle-categories');}
  createScheduledBooking(body:any){return this.request('/scheduled-bookings',{method:'POST',body:JSON.stringify(body)});}
  myBookings(){return this.request('/scheduled-bookings');}
  bookingOffers(id:string){return this.request('/scheduled-bookings/'+id+'/offers');}
  acceptOffer(bookingId:string,offerId:string){return this.request('/scheduled-bookings/'+bookingId+'/offers/'+offerId+'/accept',{method:'POST'});}
}
