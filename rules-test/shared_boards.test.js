// Firestore rules tests for sharedBoards/{id} and its places subcollection
// (see ../firestore.rules). Run from this directory with the emulator:
//   JAVA_HOME=... npm run test:emulator
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const CODE = 'abcdefghijklmnopqrstuvwxyz0123';
const BOARD = 'board1';

let env;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-cheaptripchip',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

function baseBoard(overrides = {}) {
  return {
    ownerId: 'alice',
    ownerName: 'Alice',
    name: 'Tokyo',
    emoji: '🗼',
    sections: [{ title: 'Food', placeIds: ['p1'] }],
    members: { alice: 'owner', eddie: 'editor', vera: 'viewer' },
    memberIds: ['alice', 'eddie', 'vera'],
    memberNames: { alice: 'Alice', eddie: 'Eddie', vera: 'Vera' },
    linkRole: 'viewer',
    inviteCode: CODE,
    includeOwnerNotes: false,
    ...overrides,
  };
}

function place(id = 'p1', overrides = {}) {
  return {
    id,
    name: 'Ramen',
    areaLabel: 'Shibuya',
    region: 'Tokyo',
    category: 'food',
    location: { lat: 35.6, lng: 139.7 },
    descriptionEn: '',
    originalCaption: '',
    address: '',
    hours: '',
    sourceHandle: '@x',
    sourcePlatform: 'instagram',
    award: null,
    matchConfident: true,
    rating: null,
    reviewCount: null,
    priceRange: null,
    photoUrls: [],
    isFavorite: false,
    myScore: null,
    myNotes: '',
    myPhotoAt: null,
    restaurantType: null,
    countryCode: 'JP',
    ...overrides,
  };
}

async function seed(board = baseBoard()) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'sharedBoards', BOARD), board);
    await setDoc(doc(db, 'sharedBoards', BOARD, 'places', 'p1'), place());
  });
}

const db = (uid) => (uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());
const boardRef = (uid) => doc(db(uid), 'sharedBoards', BOARD);

function joinUpdate(uid, role, code = CODE) {
  return {
    [`members.${uid}`]: role,
    memberIds: arrayUnion(uid),
    [`memberNames.${uid}`]: 'Newbie',
    joinCode: code,
    updatedAt: serverTimestamp(),
  };
}

beforeEach(async () => {
  await env.clearFirestore();
  await seed();
});

describe('read', () => {
  it('members can read the board and its places', async () => {
    for (const uid of ['alice', 'eddie', 'vera']) {
      await assertSucceeds(getDoc(boardRef(uid)));
      await assertSucceeds(getDoc(doc(db(uid), 'sharedBoards', BOARD, 'places', 'p1')));
    }
  });

  it('non-members and signed-out users cannot read', async () => {
    await assertFails(getDoc(boardRef('mallory')));
    await assertFails(getDoc(boardRef(null)));
    await assertFails(getDoc(doc(db('mallory'), 'sharedBoards', BOARD, 'places', 'p1')));
  });

  it('the Boards-tab query (memberIds array-contains uid) is allowed', async () => {
    const q = query(collection(db('vera'), 'sharedBoards'), where('memberIds', 'array-contains', 'vera'));
    await assertSucceeds(getDocs(q));
  });

  it('listing without the membership filter is denied', async () => {
    await assertFails(getDocs(collection(db('vera'), 'sharedBoards')));
  });
});

describe('create', () => {
  it('owner creates with only themself as owner', async () => {
    const ref = doc(db('bob'), 'sharedBoards', 'new');
    await assertSucceeds(
      setDoc(ref, baseBoard({ ownerId: 'bob', members: { bob: 'owner' }, memberIds: ['bob'], memberNames: { bob: 'Bob' } })),
    );
  });

  it('cannot create for someone else or with extra members', async () => {
    await assertFails(
      setDoc(doc(db('bob'), 'sharedBoards', 'x'), baseBoard({ ownerId: 'alice', members: { alice: 'owner' }, memberIds: ['alice'], memberNames: {} })),
    );
    await assertFails(
      setDoc(doc(db('bob'), 'sharedBoards', 'y'), baseBoard({ ownerId: 'bob', members: { bob: 'owner', eve: 'editor' }, memberIds: ['bob', 'eve'], memberNames: {} })),
    );
  });

  it('rejects a short invite code', async () => {
    await assertFails(
      setDoc(doc(db('bob'), 'sharedBoards', 'z'), baseBoard({ ownerId: 'bob', members: { bob: 'owner' }, memberIds: ['bob'], memberNames: {}, inviteCode: 'short' })),
    );
  });
});

describe('owner updates', () => {
  it('can rename, change link role, reset link, change roles, remove members', async () => {
    await assertSucceeds(updateDoc(boardRef('alice'), { name: 'Osaka', linkRole: 'editor', inviteCode: 'z'.repeat(24) }));
    await assertSucceeds(updateDoc(boardRef('alice'), { linkRole: null }));
    await assertSucceeds(updateDoc(boardRef('alice'), { 'members.vera': 'editor' }));
    await assertSucceeds(
      updateDoc(boardRef('alice'), {
        'members.vera': deleteField(),
        'memberNames.vera': deleteField(),
        memberIds: ['alice', 'eddie'],
      }),
    );
  });

  it('cannot transfer ownership, desync memberIds, or mint a second owner', async () => {
    await assertFails(updateDoc(boardRef('alice'), { ownerId: 'eddie' }));
    await assertFails(updateDoc(boardRef('alice'), { 'members.vera': deleteField() }));
    await assertFails(updateDoc(boardRef('alice'), { 'members.vera': 'owner' }));
    await assertFails(updateDoc(boardRef('alice'), { linkRole: 'owner' }));
  });

  it('can delete the board; others cannot', async () => {
    await assertFails(deleteDoc(boardRef('eddie')));
    await assertFails(deleteDoc(boardRef('vera')));
    await assertSucceeds(deleteDoc(boardRef('alice')));
  });
});

describe('editor', () => {
  it('can change sections only', async () => {
    await assertSucceeds(updateDoc(boardRef('eddie'), { sections: [], updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(boardRef('eddie'), { name: 'Mine now' }));
    await assertFails(updateDoc(boardRef('eddie'), { linkRole: 'editor' }));
    await assertFails(updateDoc(boardRef('eddie'), { 'members.vera': 'editor' }));
  });

  it('can write and delete places', async () => {
    const ref = doc(db('eddie'), 'sharedBoards', BOARD, 'places', 'p2');
    await assertSucceeds(setDoc(ref, place('p2')));
    await assertSucceeds(deleteDoc(ref));
  });
});

describe('viewer', () => {
  it('cannot change the board or its places', async () => {
    await assertFails(updateDoc(boardRef('vera'), { sections: [] }));
    await assertFails(setDoc(doc(db('vera'), 'sharedBoards', BOARD, 'places', 'p2'), place('p2')));
    await assertFails(deleteDoc(doc(db('vera'), 'sharedBoards', BOARD, 'places', 'p1')));
  });
});

describe('places size limits', () => {
  it('rejects unknown keys and oversized fields', async () => {
    const ref = doc(db('alice'), 'sharedBoards', BOARD, 'places', 'p3');
    await assertFails(setDoc(ref, place('p3', { jpeg: 'x' })));
    await assertFails(setDoc(ref, place('p3', { originalCaption: 'x'.repeat(10001) })));
    await assertFails(setDoc(ref, place('p3', { photoUrls: Array(21).fill('u') })));
    await assertSucceeds(setDoc(ref, place('p3')));
  });

  it('non-members cannot write places', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'sharedBoards', BOARD, 'places', 'p4'), place('p4')));
  });
});

describe('join via link', () => {
  it('joins with the right code and the link role, without reading first', async () => {
    await assertSucceeds(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'viewer')));
    await assertSucceeds(getDoc(boardRef('newbie')));
  });

  it('rejects a bad code', async () => {
    await assertFails(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'viewer', 'wrong-code-wrong-code-00')));
  });

  it('rejects a role other than the link role', async () => {
    await assertFails(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'editor')));
  });

  it('rejects joining while the link is off', async () => {
    await env.clearFirestore();
    await seed(baseBoard({ linkRole: null }));
    await assertFails(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'viewer')));
  });

  it('rejects joining an editor link as viewer and accepts it as editor', async () => {
    await env.clearFirestore();
    await seed(baseBoard({ linkRole: 'editor' }));
    await assertFails(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'viewer')));
    await assertSucceeds(updateDoc(boardRef('newbie'), joinUpdate('newbie', 'editor')));
  });

  it('rejects adding anyone else or touching other fields', async () => {
    await assertFails(
      updateDoc(boardRef('newbie'), { ...joinUpdate('newbie', 'viewer'), 'members.friend': 'viewer', memberIds: arrayUnion('newbie', 'friend') }),
    );
    await assertFails(updateDoc(boardRef('newbie'), { ...joinUpdate('newbie', 'viewer'), name: 'Pwned' }));
  });

  it('an existing member cannot re-join (no self demotion or promotion)', async () => {
    await assertFails(updateDoc(boardRef('alice'), joinUpdate('alice', 'viewer')));
    await assertFails(updateDoc(boardRef('vera'), joinUpdate('vera', 'viewer')));
  });

  it('joining a board that does not exist fails', async () => {
    await assertFails(updateDoc(doc(db('newbie'), 'sharedBoards', 'nope'), joinUpdate('newbie', 'viewer')));
  });
});

describe('leave', () => {
  it('a member can remove only themself', async () => {
    const leave = (uid) => ({
      [`members.${uid}`]: deleteField(),
      [`memberNames.${uid}`]: deleteField(),
      memberIds: ['alice', 'eddie', 'vera'].filter((id) => id !== uid),
      updatedAt: serverTimestamp(),
    });
    await assertFails(
      updateDoc(boardRef('vera'), {
        'members.eddie': deleteField(),
        'memberNames.eddie': deleteField(),
        memberIds: ['alice', 'vera'],
      }),
    );
    await assertFails(updateDoc(boardRef('alice'), leave('alice')));
    await assertSucceeds(updateDoc(boardRef('vera'), leave('vera')));
    await assertFails(getDoc(boardRef('vera')));
  });
});

describe('existing personal data rules', () => {
  it('still scope users/{uid} to the user', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users', 'alice', 'boards', 'b'), { id: 'b' }));
    await assertFails(getDoc(doc(db('bob'), 'users', 'alice', 'boards', 'b')));
  });
});
