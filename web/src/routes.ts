import {Routes} from '@angular/router';
import {Login} from './views/login';
import {Partner} from './views/partner';
import {Admin} from './views/admin';
import {Finance} from './views/finance';
import {Support} from './views/support';

export const routes:Routes=[
  {path:'login',component:Login},
  {path:'partner',component:Partner},
  {path:'admin',component:Admin},
  {path:'finance',component:Finance},
  {path:'support',component:Support},
  {path:'',pathMatch:'full',redirectTo:'login'}
];
