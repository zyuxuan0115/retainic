package com.retainic.app.data

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.userProfileChangeRequest
import com.retainic.app.R
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * Firebase email/password authentication plus the user's profile.
 * Ported from AuthService.swift. Exposes Compose-observable state.
 */
class AuthService(app: Application) : AndroidViewModel(app) {
    var user: FirebaseUser? by mutableStateOf(null)
        private set
    var profile: UserProfile? by mutableStateOf(null)
        private set
    var errorMessage: String? by mutableStateOf(null)
    var isWorking: Boolean by mutableStateOf(false)
        private set

    private val auth = FirebaseAuth.getInstance()

    val isAuthenticated: Boolean get() = user != null
    val uid: String? get() = user?.uid
    val displayName: String? get() = user?.displayName
    val email: String? get() = user?.email

    private val authListener = FirebaseAuth.AuthStateListener { firebaseAuth ->
        val u = firebaseAuth.currentUser
        user = u
        if (u != null) {
            viewModelScope.launch { loadProfile(u.uid) }
        } else {
            profile = null
        }
    }

    init {
        auth.addAuthStateListener(authListener)
    }

    override fun onCleared() {
        auth.removeAuthStateListener(authListener)
        super.onCleared()
    }

    private fun string(resId: Int): String = getApplication<Application>().getString(resId)

    fun register(email: String, password: String, username: String, invitationCode: String) {
        errorMessage = null
        isWorking = true
        viewModelScope.launch {
            try {
                if (!VocabRepository.isValidInvitationCode(invitationCode)) {
                    errorMessage = string(R.string.invitation_invalid)
                    return@launch
                }
                val result = auth.createUserWithEmailAndPassword(email, password).await()
                val fbUser = result.user
                if (fbUser != null) {
                    fbUser.updateProfile(userProfileChangeRequest { displayName = username }).await()
                    val newProfile = UserProfile(username = username, email = email, createdAt = Date())
                    VocabRepository.userDoc(fbUser.uid).set(newProfile).await()
                    profile = newProfile
                }
            } catch (e: Exception) {
                errorMessage = friendlyMessage(e)
            } finally {
                isWorking = false
            }
        }
    }

    fun signIn(email: String, password: String) {
        errorMessage = null
        isWorking = true
        viewModelScope.launch {
            try {
                auth.signInWithEmailAndPassword(email, password).await()
            } catch (e: Exception) {
                errorMessage = friendlyMessage(e)
            } finally {
                isWorking = false
            }
        }
    }

    fun signOut() {
        errorMessage = null
        auth.signOut()
    }

    /**
     * Changes the signed-in user's password after re-authenticating with the
     * current one. Returns whether it succeeded so the caller can dismiss.
     */
    suspend fun changePassword(currentPassword: String, newPassword: String): Boolean {
        errorMessage = null
        isWorking = true
        try {
            val current = auth.currentUser
            val userEmail = current?.email
            if (current == null || userEmail == null) {
                errorMessage = string(R.string.need_signed_in_change_pw)
                return false
            }
            val credential = EmailAuthProvider.getCredential(userEmail, currentPassword)
            current.reauthenticate(credential).await()
            current.updatePassword(newPassword).await()
            return true
        } catch (e: Exception) {
            errorMessage = when ((e as? FirebaseAuthException)?.errorCode) {
                "ERROR_WRONG_PASSWORD", "ERROR_INVALID_CREDENTIAL" ->
                    string(R.string.current_password_incorrect)
                "ERROR_REQUIRES_RECENT_LOGIN" ->
                    string(R.string.sign_in_again_change_pw)
                else -> friendlyMessage(e)
            }
            return false
        } finally {
            isWorking = false
        }
    }

    private suspend fun loadProfile(uid: String) {
        try {
            val snapshot = VocabRepository.userDoc(uid).get().await()
            profile = snapshot.toObject(UserProfile::class.java)
        } catch (_: Exception) {
            // Non-fatal: UI falls back to the Firebase displayName/email.
        }
    }

    private fun friendlyMessage(error: Exception): String {
        val code = (error as? FirebaseAuthException)?.errorCode
        return when (code) {
            "ERROR_EMAIL_ALREADY_IN_USE" -> string(R.string.email_already_registered)
            "ERROR_INVALID_EMAIL" -> string(R.string.enter_valid_email)
            "ERROR_WEAK_PASSWORD" -> string(R.string.password_min)
            "ERROR_WRONG_PASSWORD", "ERROR_USER_NOT_FOUND", "ERROR_INVALID_CREDENTIAL" ->
                string(R.string.incorrect_email_password)
            "ERROR_NETWORK_REQUEST_FAILED" -> string(R.string.network_error)
            else -> error.localizedMessage ?: string(R.string.something_wrong)
        }
    }
}
