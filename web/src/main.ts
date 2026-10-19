import {bootstrapApplication} from '@angular/platform-browser';
import {provideRouter, RouterOutlet, withComponentInputBinding} from '@angular/router';
import {Component} from '@angular/core';
import {routes} from './routes';

// Each portal (partner, VTC company, administration) renders its own
// layout with the navy sidebar of the validated mock-ups (DEC-13); the
// root only hosts the router.
@Component({selector: 'app-root', standalone: true, imports: [RouterOutlet], template: `<router-outlet/>`})
class App {}

bootstrapApplication(App, {providers: [provideRouter(routes, withComponentInputBinding())]});
