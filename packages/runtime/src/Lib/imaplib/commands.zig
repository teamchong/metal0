//! IMAP4 command constants
//!
//! Mirrors: CPython Lib/imaplib.py (commands section)

/// IMAP4 protocol commands
pub const Commands = struct {
    pub const APPEND = "APPEND";
    pub const AUTHENTICATE = "AUTHENTICATE";
    pub const CAPABILITY = "CAPABILITY";
    pub const CHECK = "CHECK";
    pub const CLOSE = "CLOSE";
    pub const COPY = "COPY";
    pub const CREATE = "CREATE";
    pub const DELETE = "DELETE";
    pub const DELETEACL = "DELETEACL";
    pub const ENABLE = "ENABLE";
    pub const EXAMINE = "EXAMINE";
    pub const EXPUNGE = "EXPUNGE";
    pub const FETCH = "FETCH";
    pub const GETACL = "GETACL";
    pub const GETANNOTATION = "GETANNOTATION";
    pub const GETQUOTA = "GETQUOTA";
    pub const GETQUOTAROOT = "GETQUOTAROOT";
    pub const ID = "ID";
    pub const IDLE = "IDLE";
    pub const LIST = "LIST";
    pub const LOGIN = "LOGIN";
    pub const LOGOUT = "LOGOUT";
    pub const LSUB = "LSUB";
    pub const MOVE = "MOVE";
    pub const NAMESPACE = "NAMESPACE";
    pub const NOOP = "NOOP";
    pub const PARTIAL = "PARTIAL";
    pub const PROXYAUTH = "PROXYAUTH";
    pub const RENAME = "RENAME";
    pub const SEARCH = "SEARCH";
    pub const SELECT = "SELECT";
    pub const SETACL = "SETACL";
    pub const SETANNOTATION = "SETANNOTATION";
    pub const SETQUOTA = "SETQUOTA";
    pub const SORT = "SORT";
    pub const STARTTLS = "STARTTLS";
    pub const STATUS = "STATUS";
    pub const STORE = "STORE";
    pub const SUBSCRIBE = "SUBSCRIBE";
    pub const THREAD = "THREAD";
    pub const UID = "UID";
    pub const UNSELECT = "UNSELECT";
    pub const UNSUBSCRIBE = "UNSUBSCRIBE";
};
