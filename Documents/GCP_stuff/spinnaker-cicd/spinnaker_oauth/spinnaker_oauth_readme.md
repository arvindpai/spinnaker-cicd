## Authentication using OAuth 2.0 in Spinnaker 

OAuth 2.0 is the preferred way authenticate and authorize third parties access to your data guarded by the identity provider. 

To confirm your identity, Spinnaker requests access to your email address from your identity provider.

####OAuth providers

Pre-configured providers

For convenience, several providers are already pre-configured. 

![](providers.png)

As an administrator, you merely have to activate one, and give the client ID and secret. 

Follow the Provider-Specific documentation to obtain your client ID and client secret.

Activate one by executing the following:

![](api_create_credentials.png)

Configure consent screen :

![](configure_consent_screen.png)

Fill in your google id,name of product
 
![](oauth_consent_screen.png)

The oauth client id screen will appear URIs

![](oauth_clientId.png)

Clicking on `Create` button will generate your client id and client secret key:

![](oauth_client.png)

Click `ok` and save those credentials

The Credentials screen will appear with your `saved` credentials

![](oauth2.png)


#### Execution of OAuth commands in Halyard for Spinnaker

In your configured Halyard-host already with a spinnaker running without Oauth :

![](login_wo_oauth.png)

Oauth commands with client id and client secret values :

![](Oauth_commands.png)

Go to the Shell Terminal and append the following commands :

![](appending_oauth_spinnaker.png)

After that execute `hal deploy apply` command :

![](hal_deploy.png)

Login to Spinnaker : using http://localhost:9000/

you will be redirected to your google account in the browser

![](selection_gflocks.png)

after selecting your appropriate google account, u will be redirected to Spinnaker.

You can view your gflocks account id near the `Search` option

![](spinnaker_with_oauth.png)

Can logout of the screen once any work is completed.

![](spinnaker_logout.png)


#### Reference URL's:

[Spinnaker authentication with OAuth 2.0](https://www.spinnaker.io/setup/security/authentication/oauth/providers/google/)