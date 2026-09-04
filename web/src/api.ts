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
  approveDriver(id:string){return this.request('/admin/drivers/'+id+'/approve',{method:'POST'});}
  approvePartner(id:string){return this.request('/admin/partners/'+id+'/approve',{method:'POST'});}
  cashDebts(){return this.request('/finance/cash-debts');}
  payables(){return this.request('/finance/payables');}
  settleDebt(id:string,amountMinor:number){return this.request('/finance/cash-debts/'+id+'/settle?amountMinor='+amountMinor,{method:'POST'});}
  supportTimeline(id:string){return this.request('/support/bookings/'+id+'/timeline');}
  createPartner(body:any){return this.request('/partner/organizations',{method:'POST',body:JSON.stringify(body)});}
  partnerFinance(id:string){return this.request('/partner/'+id+'/finance');}
}
