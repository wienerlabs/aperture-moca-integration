import type { NextAuthOptions } from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';

const POLICY_SERVICE_URL = process.env.POLICY_SERVICE_URL ?? process.env.NEXT_PUBLIC_POLICY_SERVICE_URL ?? 'http://localhost:3001';

export const authOptions: NextAuthOptions = {
  providers: [
    CredentialsProvider({
      id: 'credentials',
      name: 'Credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          throw new Error('Email and password are required');
        }

        const res = await fetch(`${POLICY_SERVICE_URL}/api/v1/auth/signin`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: credentials.email.trim().toLowerCase(),
            password: credentials.password,
          }),
        });

        const body = await res.json();

        if (!res.ok || !body.success) {
          throw new Error(body.error ?? 'Invalid email or password');
        }

        return {
          id: body.data.id,
          email: body.data.email,
          name: body.data.name,
        };
      },
    }),
    CredentialsProvider({
      id: 'wallet',
      name: 'Wallet',
      credentials: {
        wallet_address: { label: 'Wallet Address', type: 'text' },
        signature: { label: 'Signature', type: 'text' },
        message: { label: 'Message', type: 'text' },
      },
      async authorize(credentials) {
        if (!credentials?.wallet_address || !credentials?.signature || !credentials?.message) {
          throw new Error('Wallet address, signature, and message are required');
        }

        const res = await fetch(`${POLICY_SERVICE_URL}/api/v1/auth/wallet`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            wallet_address: credentials.wallet_address,
            signature: credentials.signature,
            message: credentials.message,
          }),
        });

        const body = await res.json();

        if (!res.ok || !body.success) {
          throw new Error(body.error ?? 'Wallet authentication failed');
        }

        return {
          id: body.data.id,
          email: body.data.email,
          name: body.data.wallet_address ?? body.data.name,
          image: body.data.wallet_address ?? undefined,
        };
      },
    }),
    // AIR Account (Moca) login. The browser obtains a signed AIR token via the
    // AIR Kit SDK and posts it here. We validate the token's claims (partner id,
    // expiry, bound abstract account). Production should additionally verify the
    // token signature against AIR's air-api JWKS.
    CredentialsProvider({
      id: 'air',
      name: 'AIR Account',
      credentials: {
        token: { label: 'AIR Token', type: 'text' },
        address: { label: 'Abstract Account Address', type: 'text' },
      },
      async authorize(credentials) {
        const token = credentials?.token;
        const address = credentials?.address;
        if (!token || !address) {
          throw new Error('AIR token and address are required');
        }

        let payload: { partnerId?: string; abstractAccountAddress?: string; sub?: string; exp?: number };
        try {
          const part = token.split('.')[1];
          payload = JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
        } catch {
          throw new Error('Malformed AIR token');
        }

        const expectedPartner = process.env.MOCA_PARTNER_ID ?? process.env.NEXT_PUBLIC_MOCA_PARTNER_ID;
        if (expectedPartner && payload.partnerId !== expectedPartner) {
          throw new Error('AIR token partner mismatch');
        }
        if (payload.exp && Date.now() / 1000 > payload.exp) {
          throw new Error('AIR token expired');
        }
        const account = payload.abstractAccountAddress ?? address;
        if (account.toLowerCase() !== address.toLowerCase()) {
          throw new Error('AIR token address mismatch');
        }

        return {
          id: payload.sub ?? account,
          email: `${account}@air.moca`,
          name: account,
          image: account,
        };
      },
    }),
  ],

  session: {
    strategy: 'jwt',
  },

  pages: {
    signIn: '/auth/signin',
  },

  secret: process.env.NEXTAUTH_SECRET,

  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id;
        token.email = user.email;
        token.name = user.name;
        token.walletAddress = user.image ?? undefined;
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        (session.user as { id?: string; walletAddress?: string }).id = token.id as string;
        (session.user as { walletAddress?: string }).walletAddress = token.walletAddress as string | undefined;
        session.user.name = token.name as string;
        session.user.email = token.email as string;
      }
      return session;
    },
  },
};
