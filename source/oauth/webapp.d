/++
    OAuth 2.0 client vibe.http.server integration

    Copyright: © 2016 Harry T. Vennik
    License: Subject to the terms of the MIT license, as written in the included LICENSE file.
    Authors: Harry T. Vennik
  +/
module oauth.webapp;

import oauth.settings : OAuthSettings;
import oauth.session : OAuthSession;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;

import std.datetime : Clock, SysTime;

/++
    Convenience oauth API wrapper for web applications
  +/
class OAuthWebapp
{
    private
    {
        struct SessionCacheEntry
        {
            OAuthSession session;
            SysTime timestamp;
        }

        SessionCacheEntry[string] _sessionCache;
    }

    /++
        Check if a request is from a logged in user

        Will only detect a login using the same settings. The same provider
        and clientId at least.

        Params:
            req = The request to be checked
            settings = The _settings to be used for the login check

        Returns: `true` if this request is from a logged in user.
      +/
    bool isLoggedIn(
        scope HTTPServerRequest req,
        immutable OAuthSettings settings) @safe
    {
        // For assert in oauthSession method
        version(assert) () @trusted {
            import std.variant : Variant;
            req.context["oauth.debug.login.checked"] = cast(Variant) true;
        } ();

        if (!req.session)
            return false;

        if (auto pCE = req.session.id in _sessionCache)
        {
            if (pCE.session.verify(req.session))
            {
                pCE.timestamp = Clock.currTime;
                return true;
            }
            else
                _sessionCache.remove(req.session.id);
        }
        if (auto session =
            settings ? OAuthSession.load(settings, req.session) : null)
        {
            () @trusted {
                import std.variant : Variant;
                req.context["oauth.session"] = cast(Variant) session;
            } ();

            _sessionCache[req.session.id] =
                SessionCacheEntry(session, Clock.currTime);

            return true;
        }

        return false;
    }

    /++
        Perform OAuth _login using the given _settings

        The route mapped to this method should normally match the redirectUri
        set on the settings. If multiple providers are to be supported, there
        should be a different route for each provider, all mapped to this
        method, but with different settings.

        If the request looks like a redirect back from the authentication
        server, settings.userSession is called to obtain an OAuthSession.

        Otherwise, the user agent is redirected to the authentication server.

        Params:
            req = The request
            res = Response object to be used to redirect the client to the
                authentication server
            settings = The OAuth settings that apply to this _login attempt
            scopes = (Optional) An array of identifiers specifying the scope of
                the authorization requested.
      +/
    void login(
        scope HTTPServerRequest req,
        scope HTTPServerResponse res,
        immutable OAuthSettings settings,
        in string[string] extraParams = null,
        in string[] scopes = null) @safe
    {
        // redirect from the authentication server
        if (req.session && "code" in req.query && "state" in req.query)
        {
            auto session = settings.userSession(
                req.session, req.query["state"], req.query["code"]);

            if (session)
            {
                _sessionCache[req.session.id] =
                    SessionCacheEntry(session, Clock.currTime);

                // For assert in oauthSession method
                version(assert) () @trusted {
                    import std.variant : Variant;
                    req.context["oauth.debug.login.checked"] = cast(Variant) true;
                } ();
            }
        }
        else
        {
            if (!req.session)
                req.session = res.startSession();

            res.redirect(settings.userAuthUri(req.session, extraParams, scopes));
        }
    }

    /++
        Get the OAuthSession object associated to a request.

        This method is optimized for speed. It just performs a session cache
        lookup and doesn't do any validation.

        Always make sure that either `login` or `isLoggedIn` has been
        called for a request before this method is used.

        Params:
            req = the request to get the relevant session for

        Returns: The session associated to req, or `null` if no
            session was found.
      +/
    final
    OAuthSession oauthSession(scope HTTPServerRequest req) nothrow @safe
    in
    {
        try () @trusted {
            assert (req.context.get("oauth.debug.login.checked").get!bool);
        } ();
        catch (Exception)
            assert(false);
    }
    body
    {
        try
        {
            if (auto pCM = "oauth.session" in req.context) () @trusted {
                return pCM.get!OAuthSession;
            } ();

            if (auto pCE = req.session.id in _sessionCache)
                return pCE.session;
        }
        catch (Exception) { }

        return null;
    }
}
